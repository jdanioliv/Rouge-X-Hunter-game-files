-- DataPersistenceService
-- Self-contained persistence pipeline implementing the GDD's transaction
-- architecture: MemoryStore session locks + DataStore atomic UpdateAsync
-- writes. This is the duplication defense: a profile can only be owned by one
-- live server at a time, so crashes or rapid re-joins cannot double-load
-- (and later, Greed Island cards cannot be duped through transfer races).
--
-- Flow per player:
--   join -> acquire session lock (retry, kick on failure) -> load profile ->
--   hydrate PlayerStateService + NenAffinityService -> autosave loop ->
--   leave -> settle pending consequences -> final save -> release lock.
--
-- A server only writes a profile while it can show that it owns the lock. If the
-- lock service is down, the player cannot join a live server, and a running
-- session stops saving once its last confirmation is too old to rely on.
--
-- Init() must run BEFORE the other services in Main so this service's
-- PlayerRemoving handler fires first, reading state before it is cleared.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local PlayerStateService = require(script.Parent.PlayerStateService)
local NenAffinityService = require(script.Parent.NenAffinityService)

local DataPersistenceService = {}

-- Unique identity for this server instance (JobId is empty in Studio).
local sessionId = game.JobId ~= "" and game.JobId or `studio-{HttpService:GenerateGUID(false)}`

local dataStore = nil
local lockMap = nil
local storesAvailable = false

-- Players whose profile loaded successfully; only these are ever saved,
-- so a failed load can never overwrite good data with defaults.
local loaded: { [Player]: boolean } = {}
-- Locks this server actually claimed. Only these are ever released, so a player
-- kicked because another server owns the profile cannot delete that server's lock.
local heldLocks: { [Player]: boolean } = {}
local lockConfirmedAt: { [Player]: number } = {}
local saveQueued: { [Player]: boolean } = {}
-- Newest save started per player, so a retry cannot overwrite a later save.
local saveSequence: { [Player]: number } = {}
local warnedApiUnavailable = false

local function warnApi(context: string, err: any)
	if not warnedApiUnavailable then
		warnedApiUnavailable = true
		warn(`[DataPersistence] {context} failed ({err}). If testing in Studio, enable "Studio Access to API Services". Saves are disabled until calls succeed.`)
	end
end

local function playerKey(player: Player): string
	return `player_{player.UserId}`
end

--------------------------------------------------------------------------------
-- Session locks (MemoryStore)
--------------------------------------------------------------------------------

type LockResult = "Claimed" | "HeldElsewhere" | "Unavailable"

-- Atomically claims the lock unless another live session holds it. A failed call
-- proves nothing about who owns the profile, so it is reported as its own result.
local function tryClaimLock(key: string): LockResult
	local ok, result = pcall(function()
		return lockMap:UpdateAsync(key, function(current)
			if current == nil or current == sessionId then
				return sessionId
			end
			return nil -- abort: another session owns this profile
		end, Constants.SESSION_LOCK_TTL)
	end)
	if not ok then
		warnApi("Session lock", result)
		return "Unavailable"
	end
	return if result ~= nil then "Claimed" else "HeldElsewhere"
end

local function claimLock(player: Player): LockResult
	local result = tryClaimLock(playerKey(player))
	if result == "Claimed" then
		heldLocks[player] = true
		lockConfirmedAt[player] = os.clock()
	elseif result == "HeldElsewhere" then
		heldLocks[player] = nil
		lockConfirmedAt[player] = nil
	end
	return result
end

local function acquireLock(player: Player): LockResult
	local result: LockResult = "Unavailable"
	for _ = 1, Constants.SESSION_LOCK_RETRIES do
		result = claimLock(player)
		if result == "Claimed" then
			return result
		end
		task.wait(Constants.SESSION_LOCK_RETRY_DELAY)
	end
	return result
end

local function releaseLock(player: Player)
	if not heldLocks[player] then
		return
	end
	heldLocks[player] = nil
	lockConfirmedAt[player] = nil
	pcall(function()
		-- Read first: if the lock expired during an outage, another server may own it now.
		local key = playerKey(player)
		if lockMap:GetAsync(key) == sessionId then
			lockMap:RemoveAsync(key)
		end
	end)
end

-- True when the last confirmation is recent enough that the TTL cannot have run
-- out, otherwise asks the lock service again. Yields in that second case.
local function stillOwnsLock(player: Player): boolean
	local confirmedAt = lockConfirmedAt[player]
	local safeAge = Constants.SESSION_LOCK_TTL - Constants.SESSION_LOCK_RENEW_INTERVAL
	if confirmedAt and (os.clock() - confirmedAt) < safeAge then
		return true
	end
	return claimLock(player) == "Claimed"
end

--------------------------------------------------------------------------------
-- Serialization
--------------------------------------------------------------------------------

local function buildProfile(player: Player)
	local stateData = PlayerStateService.BuildPersistedData(player)
	if not stateData then
		return nil
	end
	local nenData = NenAffinityService.BuildPersistedData(player)

	stateData.affinity = nenData.affinity
	stateData.learnedNodes = nenData.learnedNodes
	stateData.schemaVersion = Constants.DATA_SCHEMA_VERSION
	return stateData
end

-- Returns false if the state never appeared, so the caller cannot mark as loaded
-- a profile that was not applied and later save defaults over it.
local function hydrate(player: Player, data): boolean
	-- PlayerStateService creates state synchronously on PlayerAdded, but our
	-- load runs async; wait briefly for the state to exist.
	local deadline = os.clock() + 10
	while not PlayerStateService.GetState(player) do
		if os.clock() > deadline or not player.Parent then
			return false
		end
		task.wait(0.1)
	end
	PlayerStateService.ApplyPersistedData(player, data)
	NenAffinityService.ApplyPersistedData(player, data)
	return true
end

--------------------------------------------------------------------------------
-- Load / save
--------------------------------------------------------------------------------

local function loadProfile(player: Player)
	for _ = 1, 3 do
		local ok, data = pcall(function()
			return dataStore:GetAsync(playerKey(player))
		end)
		if ok then
			return true, data
		end
		warnApi("Load", data)
		task.wait(1)
	end
	return false, nil
end

-- All writes are atomic UpdateAsync (never SetAsync) per the GDD spec.
local function saveProfile(player: Player): boolean
	if not loaded[player] then
		return false
	end
	-- Built before anything yields: on leave, state is cleared by the next
	-- PlayerRemoving handler as soon as this thread waits.
	local profile = buildProfile(player)
	if not profile then
		return false
	end

	local sequence = (saveSequence[player] or 0) + 1
	saveSequence[player] = sequence

	if not stillOwnsLock(player) then
		warn(`[DataPersistence] Skipped saving {player.Name}: this server cannot confirm it owns the profile`)
		return false
	end

	for _ = 1, 2 do
		-- A newer save holds newer data. Writing this one now could undo a wipe.
		if saveSequence[player] ~= sequence then
			return false
		end
		local ok, err = pcall(function()
			dataStore:UpdateAsync(playerKey(player), function(_old)
				return profile
			end)
		end)
		if ok then
			return true
		end
		warnApi("Save", err)
		task.wait(1)
	end
	warn(`[DataPersistence] Save failed for {player.Name}`)
	return false
end

--------------------------------------------------------------------------------
-- Public save API
--------------------------------------------------------------------------------

-- Forces an immediate atomic write for one player. Used by irreversible
-- progression events that must survive a server crash the instant they happen
-- (Water Divination awakening, character wipe). Yields; call from a task thread
-- if the caller cannot block. Returns false when the profile never loaded, so a
-- failed load can still never overwrite good data.
function DataPersistenceService.SaveNow(player: Player): boolean
	if not loaded[player] then
		return false
	end
	return saveProfile(player)
end

-- For changes that happen often, like skill purchases: saves once within
-- SAVE_COALESCE_SECONDS, however many requests arrive. Does not yield.
function DataPersistenceService.RequestSave(player: Player)
	if saveQueued[player] or not loaded[player] then
		return
	end
	saveQueued[player] = true
	task.delay(Constants.SAVE_COALESCE_SECONDS, function()
		saveQueued[player] = nil
		if player.Parent and loaded[player] then
			saveProfile(player)
		end
	end)
end

function DataPersistenceService.IsLoaded(player: Player): boolean
	return loaded[player] == true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	task.spawn(function()
		if not storesAvailable then
			return
		end

		local lockResult = acquireLock(player)
		if lockResult == "HeldElsewhere" and not RunService:IsStudio() then
			player:Kick("Your data is still saving from a previous session. Please rejoin in a minute.")
			return
		elseif lockResult ~= "Claimed" then
			-- Studio only reaches here with a lock left by a stopped test, or no API access.
			if RunService:IsStudio() then
				warn(`[DataPersistence] Continuing without saves for {player.Name} (Studio)`)
			else
				player:Kick("Our data service is unavailable right now. Please rejoin in a minute.")
			end
			return
		end

		local ok, data = loadProfile(player)
		if not ok then
			if RunService:IsStudio() then
				warn(`[DataPersistence] Continuing without saves for {player.Name} (Studio)`)
			else
				releaseLock(player)
				player:Kick("Your data failed to load. Please rejoin.")
			end
			return
		end

		if data ~= nil and not hydrate(player, data) then
			releaseLock(player)
			if player.Parent then
				player:Kick("Your data failed to load. Please rejoin.")
			end
			return
		end
		if player.Parent then
			loaded[player] = true
		else
			releaseLock(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	-- Signal handlers run now, up to their first yield, so anything they change is
	-- in the profile built below.
	PlayerStateService.PlayerLeaving:Fire(player)

	if loaded[player] then
		saveProfile(player)
	end
	loaded[player] = nil
	saveQueued[player] = nil
	saveSequence[player] = nil
	if storesAvailable then
		releaseLock(player)
	end
end

function DataPersistenceService.Init()
	local ok, err = pcall(function()
		dataStore = DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
		lockMap = MemoryStoreService:GetSortedMap(Constants.SESSION_LOCK_MAP_NAME)
	end)
	storesAvailable = ok
	if not ok then
		warnApi("Store initialization", err)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- A wipe must hit the DataStore immediately: crashing the server right
	-- after losing the last Soul Node cannot resurrect the character.
	-- Deferred so every other CharacterWiped handler clears its data first, or this
	-- write would keep the old affinity and skill nodes.
	PlayerStateService.CharacterWiped:Connect(function(player)
		task.defer(function()
			if player.Parent and loaded[player] then
				saveProfile(player)
			end
		end)
	end)

	-- Any Soul Node loss is irreversible. The final node is covered by the wipe above.
	PlayerStateService.SoulNodeLost:Connect(function(player, remainingNodes)
		if remainingNodes > 0 and player.Parent and loaded[player] then
			saveProfile(player)
		end
	end)

	-- Iteration helper: saves/renewals yield, and Luau forbids adding new
	-- keys to a table being iterated, so snapshot the player list first.
	local function loadedPlayers(): { Player }
		local list = {}
		for player in loaded do
			table.insert(list, player)
		end
		return list
	end

	-- Periodic autosave, staggered to spread request budget.
	task.spawn(function()
		while true do
			task.wait(Constants.AUTOSAVE_INTERVAL)
			for _, player in loadedPlayers() do
				if player.Parent and loaded[player] then
					saveProfile(player)
					task.wait(0.5)
				end
			end
		end
	end)

	-- Session lock renewal keeps live sessions owning their profiles.
	task.spawn(function()
		while true do
			task.wait(Constants.SESSION_LOCK_RENEW_INTERVAL)
			if storesAvailable then
				for _, player in loadedPlayers() do
					if player.Parent and loaded[player] and claimLock(player) == "HeldElsewhere" then
						-- Our lock expired and another server took the profile. Stop
						-- writing, or this server would overwrite that session's data.
						loaded[player] = nil
						warn(`[DataPersistence] Lost the session lock for {player.Name}`)
						player:Kick("Your character was opened on another server.")
					end
				end
			end
		end
	end)

	-- Flush everything on shutdown.
	game:BindToClose(function()
		for _, player in loadedPlayers() do
			saveProfile(player)
			releaseLock(player)
		end
		-- Players still loading hold a lock too.
		for player in table.clone(heldLocks) do
			releaseLock(player)
		end
	end)
end

return DataPersistenceService
