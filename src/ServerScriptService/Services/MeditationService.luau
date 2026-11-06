--!strict
-- MeditationService
-- The SAFE aura-opening path (GDD section 3). Where the Gehaku catalyst rolls
-- the 5-tier outcome wheel and can cost a Soul Node, Natural Meditation cannot
-- kill, mutilate, or apply the Bypassed penalty. It only costs time and the
-- discipline to stay undisturbed - filling meditationProgress to 100, which is
-- what gates the Water Divination ceremony.
--
-- Trust model: the client runs a breathing/rhythm minigame and reports each
-- successful beat with FocusTick. It reports ONLY that a beat happened - never
-- when, and never how much progress to award. Every accepted tick is stamped
-- with the server clock and must be at least TICK_INTERVAL apart (minus network
-- tolerance), so a client spamming FocusTick gains nothing beyond the honest
-- rate. Progress, interruption, and immobilization are all server-owned.
--
-- Interruption sources, all server-side:
--   * any HP loss (PlayerStateService.PlayerDamaged, plus a HealthChanged
--     catch-all for environmental damage that bypasses ApplyDamage)
--   * being downed
--   * moving the character further than MOVEMENT_TOLERANCE from the anchor
--   * going quiet for longer than TICK_INTERVAL + MISSED_TICK_GRACE
--   * respawn, character removal, or leaving

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerStateService = require(script.Parent.PlayerStateService)

local MeditationService = {}

-- Fired when focus reaches MAX_PROGRESS. Nothing connects yet: it is for future
-- tutorial prompts. WaterDivinationService reads progress on demand instead.
MeditationService.FocusCompleted = Signal.new() -- (player)
MeditationService.MeditationEnded = Signal.new() -- (player, reason, focusProgress)

local MEDITATION = Constants.MEDITATION

-- Per-player live session. Absent entry == not meditating.
local sessions: { [Player]: Types.MeditationState } = {}

-- Position the session was started from; drift beyond MOVEMENT_TOLERANCE breaks it.
local anchors: { [Player]: Vector3 } = {}

-- Humanoid values captured before immobilization so they can be restored exactly.
local restorePoints: { [Player]: { walkSpeed: number, jumpPower: number } } = {}

-- Guards the HealthChanged catch-all against re-entering on the heal side.
local lastKnownHealth: { [Player]: number } = {}

local toggleFunction = Remotes.GetFunction("ToggleMeditation")
local focusTickRemote = Remotes.Get("FocusTick")

-- AUTO_AWAKEN_DEBUG spawns Studio players already awakened, which would make the
-- whole meditation -> divination flow permanently unreachable in a playtest.
-- Same override the other Nen gates use, in the opposite direction.
local function isStudioDebug(): boolean
	return RunService:IsStudio() and Constants.AUTO_AWAKEN_DEBUG
end

--------------------------------------------------------------------------------
-- Character helpers
--------------------------------------------------------------------------------

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Server-authoritative immobilization. The client sinks its own movement input
-- too, but that is purely for responsiveness - this is the binding constraint.
local function immobilize(player: Player)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	restorePoints[player] = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
	}
	humanoid.WalkSpeed = MEDITATION.WALK_SPEED
	humanoid.JumpPower = 0
end

local function releaseMovement(player: Player)
	local restore = restorePoints[player]
	restorePoints[player] = nil
	if not restore then
		return
	end

	-- Never hand movement back to a downed player: PlayerStateService pinned
	-- them at zero on purpose and owns their release.
	local state = PlayerStateService.GetState(player)
	if state and state.isDowned then
		return
	end

	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = restore.walkSpeed
		humanoid.JumpPower = restore.jumpPower
	end
end

-- Published for every nearby client, mirroring how PlayerStateService publishes
-- AuraState. No client reads it yet.
local function setMeditatingAttribute(player: Player, meditating: boolean)
	local character = player.Character
	if character then
		character:SetAttribute("IsMeditating", meditating)
	end
end

--------------------------------------------------------------------------------
-- Session lifecycle
--------------------------------------------------------------------------------

-- Writes live focus back into the persisted slice on PlayerState.
local function flushProgress(player: Player)
	local session = sessions[player]
	if session then
		PlayerStateService.SetMeditationProgress(player, session.focusProgress)
	end
end

local function endSession(player: Player, reason: string)
	local session = sessions[player]
	if not session then
		return
	end

	flushProgress(player)
	local finalProgress = session.focusProgress

	session.isMeditating = false
	sessions[player] = nil
	anchors[player] = nil
	lastKnownHealth[player] = nil

	PlayerStateService.SetMeditating(player, false)
	setMeditatingAttribute(player, false)
	releaseMovement(player)

	MeditationService.MeditationEnded:Fire(player, reason, finalProgress)
end

-- Returns (started, reason). Every rejection reason is safe to show the client.
local function startSession(player: Player): (boolean, string?)
	if sessions[player] then
		return false, "AlreadyMeditating"
	end

	local state = PlayerStateService.GetState(player)
	if not state then
		return false, "NoState"
	end
	if state.nenAwakened and not isStudioDebug() then
		return false, "AlreadyAwakened"
	end
	if state.isDowned or state.isGuardBroken then
		return false, "Incapacitated"
	end
	if PlayerStateService.IsInCombat(player) then
		return false, "InCombat"
	end
	if state.meditationProgress >= MEDITATION.MAX_PROGRESS then
		return false, "AlreadyFocused"
	end

	local humanoid = getHumanoid(player)
	local rootPart = getRootPart(player)
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return false, "NoCharacter"
	end

	local now = os.clock()
	sessions[player] = {
		isMeditating = true,
		focusProgress = state.meditationProgress,
		-- Seeded to now so the very first tick still has to wait a full interval.
		lastTickTimestamp = now,
	}
	anchors[player] = rootPart.Position
	lastKnownHealth[player] = humanoid.Health

	PlayerStateService.SetMeditating(player, true)
	setMeditatingAttribute(player, true)
	immobilize(player)

	return true, nil
end

--------------------------------------------------------------------------------
-- Focus ticks (client rhythm hits, server-rate-limited)
--------------------------------------------------------------------------------

local function onFocusTick(player: Player)
	local session = sessions[player]
	if not session or not session.isMeditating then
		return
	end

	-- The client never supplies a timestamp; only the server clock counts.
	-- Ticks arriving faster than the honest cadence are dropped outright rather
	-- than queued, so spamming the remote can never outpace normal play.
	local now = os.clock()
	if (now - session.lastTickTimestamp) < (MEDITATION.TICK_INTERVAL - Constants.NETWORK_TOLERANCE) then
		return
	end

	session.lastTickTimestamp = now
	session.focusProgress = math.clamp(session.focusProgress + MEDITATION.TICK_GAIN, 0, MEDITATION.MAX_PROGRESS)
	PlayerStateService.SetMeditationProgress(player, session.focusProgress)

	if session.focusProgress >= MEDITATION.MAX_PROGRESS then
		endSession(player, "Completed")
		MeditationService.FocusCompleted:Fire(player)
	end
end

--------------------------------------------------------------------------------
-- Watchdog: movement drift and missed beats
--------------------------------------------------------------------------------

-- Decides why (if at all) a session should end this frame.
local function evaluateBreak(player: Player, session: Types.MeditationState, now: number): string?
	local humanoid = getHumanoid(player)
	local rootPart = getRootPart(player)
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return "CharacterLost"
	end

	if MEDITATION.BREAK_ON_MOVEMENT then
		local anchor = anchors[player]
		if anchor and (rootPart.Position - anchor).Magnitude > MEDITATION.MOVEMENT_TOLERANCE then
			return "Moved"
		end
	end

	-- Rhythm abandoned: the player walked away from the keyboard or the client
	-- stopped reporting beats.
	if (now - session.lastTickTimestamp) > (MEDITATION.TICK_INTERVAL + MEDITATION.MISSED_TICK_GRACE) then
		return "LostFocus"
	end

	return nil
end

local function stepSessions()
	local now = os.clock()

	-- Collected first, ended after: endSession fires MeditationEnded, whose
	-- handlers run immediately on spawned threads and could start a new session,
	-- and adding keys to a table mid-traversal is undefined in Luau.
	local expired: { { player: Player, reason: string } } = {}
	for player, session in sessions do
		if not player.Parent then
			continue
		end
		local reason = evaluateBreak(player, session, now)
		if reason then
			table.insert(expired, { player = player, reason = reason })
		end
	end

	for _, entry in expired do
		endSession(entry.player, entry.reason)
	end
end

--------------------------------------------------------------------------------
-- Public API (consumed by WaterDivinationService)
--------------------------------------------------------------------------------

function MeditationService.GetSession(player: Player): Types.MeditationState?
	return sessions[player]
end

function MeditationService.IsMeditating(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.isMeditating
end

function MeditationService.GetProgress(player: Player): number
	local session = sessions[player]
	if session then
		return session.focusProgress
	end
	return PlayerStateService.GetMeditationProgress(player)
end

-- Ends an active session from outside, for any future cutscene/teleport system.
-- Safe to call when idle.
function MeditationService.StopMeditation(player: Player, reason: string?)
	endSession(player, reason or "Cancelled")
end

-- Consumes the accumulated focus. Called by WaterDivinationService once the
-- ritual has actually succeeded, so a failed attempt never burns progress.
function MeditationService.ResetProgress(player: Player)
	endSession(player, "Consumed")
	PlayerStateService.SetMeditationProgress(player, 0)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MeditationService.Init()
	-- Client asks to enter/leave; the server decides and reports the truth back.
	toggleFunction.OnServerInvoke = function(player)
		if sessions[player] then
			endSession(player, "PlayerStopped")
			return {
				isMeditating = false,
				focusProgress = PlayerStateService.GetMeditationProgress(player),
				maxProgress = MEDITATION.MAX_PROGRESS,
				tickInterval = MEDITATION.TICK_INTERVAL,
			}
		end

		local started, reason = startSession(player)
		return {
			isMeditating = started,
			reason = reason,
			focusProgress = PlayerStateService.GetMeditationProgress(player),
			maxProgress = MEDITATION.MAX_PROGRESS,
			tickInterval = MEDITATION.TICK_INTERVAL,
		}
	end

	focusTickRemote.OnServerEvent:Connect(function(player)
		onFocusTick(player)
	end)

	-- Damage interrupt. ApplyDamage is the funnel for all combat damage.
	if MEDITATION.BREAK_ON_DAMAGE then
		PlayerStateService.PlayerDamaged:Connect(function(player)
			if sessions[player] then
				endSession(player, "Damaged")
			end
		end)
	end

	PlayerStateService.PlayerDowned:Connect(function(player)
		if sessions[player] then
			endSession(player, "Downed")
		end
	end)

	-- Respawns and character despawns must not leave a session (or a zeroed
	-- WalkSpeed) behind on the new character.
	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end

		-- Catch-all for damage that never goes through ApplyDamage (falls,
		-- environmental hazards, future scripted damage).
		humanoid.HealthChanged:Connect(function(health)
			local previous = lastKnownHealth[player]
			lastKnownHealth[player] = health
			if not MEDITATION.BREAK_ON_DAMAGE or not sessions[player] then
				return
			end
			if previous and health < previous then
				endSession(player, "Damaged")
			end
		end)

		humanoid.Died:Connect(function()
			endSession(player, "Died")
		end)
	end

	local function onPlayerAdded(player: Player)
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			-- Drop the restore point BEFORE ending the session: it captured the
			-- old body's WalkSpeed, and releaseMovement would otherwise stamp it
			-- onto the freshly spawned humanoid.
			restorePoints[player] = nil
			endSession(player, "Respawned")
			watchCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			restorePoints[player] = nil
			endSession(player, "CharacterRemoved")
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- This runs after the final save, so it is cleanup only. Partial focus is
		-- already saved, because every accepted tick commits it to PlayerState.
		endSession(player, "Left")
		restorePoints[player] = nil
		lastKnownHealth[player] = nil
	end)

	-- A wipe erases progression entirely, meditation focus included.
	PlayerStateService.CharacterWiped:Connect(function(player)
		endSession(player, "Wiped")
		PlayerStateService.SetMeditationProgress(player, 0)
	end)

	RunService.Heartbeat:Connect(stepSessions)
end

return MeditationService
