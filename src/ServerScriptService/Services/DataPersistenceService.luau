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
--   leave -> final save -> release lock.
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

-- Atomically claims the lock unless another live session holds it.
local function tryClaimLock(key: string): boolean
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
		-- Treat API failure as "no locking available" rather than blocking play.
		return true
	end
	return result ~= nil
end

local function acquireLock(player: Player): boolean
	local key = playerKey(player)
	for _ = 1, Constants.SESSION_LOCK_RETRIES do
		if tryClaimLock(key) then
			return true
		end
		task.wait(Constants.SESSION_LOCK_RETRY_DELAY)
	end
	return false
end

local function releaseLock(player: Player)
	pcall(function()
		lockMap:RemoveAsync(playerKey(player))
	end)
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

local function hydrate(player: Player, data)
	-- PlayerStateService creates state synchronously on PlayerAdded, but our
	-- load runs async; wait briefly for the state to exist.
	local deadline = os.clock() + 10
	while not PlayerStateService.GetState(player) do
		if os.clock() > deadline or not player.Parent then
			return
		end
		task.wait(0.1)
	end
	PlayerStateService.ApplyPersistedData(player, data)
	NenAffinityService.ApplyPersistedData(player, data)
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
	local profile = buildProfile(player)
	if not profile then
		return false
	end

	for _ = 1, 2 do
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

		if not acquireLock(player) then
			player:Kick("Your data is still saving from a previous session. Please rejoin in a minute.")
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

		if data ~= nil then
			hydrate(player, data)
		end
		if player.Parent then
			loaded[player] = true
		else
			releaseLock(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	if loaded[player] then
		saveProfile(player)
	end
	loaded[player] = nil
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
	PlayerStateService.CharacterWiped:Connect(function(player)
		if player.Parent and loaded[player] then
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
					if player.Parent and loaded[player] then
						tryClaimLock(playerKey(player))
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
	end)
end

return DataPersistenceService
