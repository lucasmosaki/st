--!strict
-- RoundService: the central finite state machine that drives the entire match loop.
-- All state transitions are server-authoritative.
--
-- Round flow:
--   Lobby → Intermission → MapVoting → MapLoading → TeamAssignment
--       → Preparation → ActiveRound → WinCondition → Rewards → Cleanup → Lobby

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local StateMachine = require(ReplicatedStorage.Shared.Utility.StateMachine)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

local NetworkService = require(script.Parent.NetworkService)
local TeamService = require(script.Parent.TeamService)
local MapService = require(script.Parent.MapService)
local LootService = require(script.Parent.LootService)
local CombatService = require(script.Parent.CombatService)
local AbilityService = require(script.Parent.AbilityService)
local ProgressionService = require(script.Parent.ProgressionService)

type MapConfig = Types.MapConfig
type RoundSummary = Types.RoundSummary

-- ── RoundService ──────────────────────────────────────────────────────────────

local RoundService = {}

RoundService.RoundStarted = Signal.new() :: Signal.Signal<MapConfig>
RoundService.RoundEnded = Signal.new() :: Signal.Signal<RoundSummary>

-- The FSM instance
local _fsm: StateMachine.StateMachine

-- Round state
local _currentMap: MapConfig? = nil
local _roundTimer: number = 0
local _timerThread: thread? = nil
local _winEvalThread: thread? = nil
local _lobbyThread: thread? = nil
local _winResult: { WinningTeam: string, Reason: string }? = nil
local _roundConnections: { RBXScriptConnection } = {}  -- disconnected on ActiveRound exit

-- ── Utility ───────────────────────────────────────────────────────────────────

local function broadcast(message: string, data: any?)
	NetworkService.FireAllClients(Constants.NETWORK.ROUND_STATE_CHANGED, message, data)
end

local function broadcastTimer(remaining: number)
	NetworkService.FireAllClients(Constants.NETWORK.ROUND_TIMER_SYNC, remaining)
end

local function notify(msg: string, notifType: string?)
	NetworkService.FireAllClients(Constants.NETWORK.NOTIFICATION, {
		Type = notifType or "Info",
		Message = msg,
	})
end

local function cancelThread(t: thread?)
	if t then
		task.cancel(t)
	end
end

local function countdown(duration: number, label: string): thread
	return task.spawn(function()
		local remaining = duration
		while remaining > 0 do
			broadcastTimer(remaining)
			task.wait(1)
			remaining -= 1
		end
		broadcastTimer(0)
	end)
end

-- ── Win Condition Evaluation ──────────────────────────────────────────────────

local function evaluateWinConditions(): { WinningTeam: string, Reason: string }?
	-- SPECops win: all robbers eliminated
	local aliveRobbers = CombatService.GetAliveRobbers()
	if #aliveRobbers == 0 and #TeamService.GetRobbers() > 0 then
		return { WinningTeam = "SPECops", Reason = "AllRobbersEliminated" }
	end

	-- SPECops win: round timer expired
	if _roundTimer <= 0 then
		return { WinningTeam = "SPECops", Reason = "TimerExpired" }
	end

	-- Robbers win: extracted loot meets threshold
	local currentMap = _currentMap
	if currentMap then
		local threshold = currentMap.TotalLootValue * Constants.LOOT.TEAM_WIN_LOOT_PERCENT
		if LootService.GetExtractedTotal() >= threshold then
			return { WinningTeam = "Robbers", Reason = "RobbersExtracted" }
		end
	end

	return nil
end

-- ── State Machine Definitions ─────────────────────────────────────────────────

local function buildFSM(): StateMachine.StateMachine
	return StateMachine.new("Lobby", {

		Lobby = {
			Transitions = { "Intermission" },
			OnEnter = function(_prev)
				TeamService.ReturnToLobby()
				broadcast("Lobby")
				notify("Waiting for players...", "Info")

				_lobbyThread = task.spawn(function()
					while true do
						task.wait(2)
						local count = #Players:GetPlayers()
						if count >= Constants.TIMING.LOBBY_MIN_PLAYERS then
							_fsm:To("Intermission")
							return
						end
					end
				end)
			end,
			OnExit = function(_next)
				cancelThread(_lobbyThread)
				_lobbyThread = nil
			end,
		},

		Intermission = {
			Transitions = { "MapVoting", "Lobby" },
			OnEnter = function(_prev)
				broadcast("Intermission")
				notify("Match starting soon!", "Info")

				task.spawn(function()
					local t = countdown(Constants.TIMING.INTERMISSION_DURATION, "Intermission")
					task.wait(Constants.TIMING.INTERMISSION_DURATION)
					cancelThread(t)

					if #Players:GetPlayers() < Constants.TIMING.LOBBY_MIN_PLAYERS then
						_fsm:To("Lobby")
					else
						_fsm:To("MapVoting")
					end
				end)
			end,
		},

		MapVoting = {
			Transitions = { "MapLoading", "Lobby" },
			OnEnter = function(_prev)
				broadcast("MapVoting")

				task.spawn(function()
					local selectedMap = MapService.RunVoting(Constants.TIMING.MAP_VOTING_DURATION)
					_currentMap = selectedMap
					_fsm:To("MapLoading")
				end)
			end,
		},

		MapLoading = {
			Transitions = { "TeamAssignment", "Lobby" },
			OnEnter = function(_prev)
				broadcast("MapLoading", _currentMap and _currentMap.Id)
				notify("Loading map: " .. ((_currentMap and _currentMap.DisplayName) or "Unknown"), "Info")

				task.spawn(function()
					if _currentMap then
						MapService.LoadMap(_currentMap)
					end
					task.wait(Constants.TIMING.MAP_LOADING_DURATION)
					_fsm:To("TeamAssignment")
				end)
			end,
		},

		TeamAssignment = {
			Transitions = { "Preparation" },
			OnEnter = function(_prev)
				broadcast("TeamAssignment")

				task.spawn(function()
					TeamService.AssignTeams()
					notify("Teams have been assigned!", "Info")
					task.wait(Constants.TIMING.TEAM_ASSIGNMENT_DURATION)
					_fsm:To("Preparation")
				end)
			end,
		},

		Preparation = {
			Transitions = { "ActiveRound" },
			OnEnter = function(_prev)
				broadcast("Preparation")
				notify("Preparation phase — plan your approach!", "Warning")

				-- Spawn all players at their team's spawn points
				for _, player in Players:GetPlayers() do
					if not player.Character then
						player:LoadCharacter()
					end
					task.wait(0.05)
					local team = TeamService.GetTeamOf(player)
					MapService.SpawnPlayer(player, team)
				end

				-- Freeze movement in preparation (via server-side attribute)
				for _, player in Players:GetPlayers() do
					local char = player.Character
					if char then
						local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
						if hum then
							hum.WalkSpeed = 0
							hum.JumpPower = 0
						end
					end
				end

				task.spawn(function()
					local t = countdown(Constants.TIMING.PREPARATION_DURATION, "Preparation")
					task.wait(Constants.TIMING.PREPARATION_DURATION)
					cancelThread(t)
					_fsm:To("ActiveRound")
				end)
			end,
			OnExit = function(_next)
				-- Restore movement
				for _, player in Players:GetPlayers() do
					local char = player.Character
					if char then
						local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
						if hum then
							hum.WalkSpeed = 16
							hum.JumpPower = 50
						end
					end
				end
			end,
		},

		ActiveRound = {
			Transitions = { "WinCondition" },
			OnEnter = function(_prev)
				local map = _currentMap
				if not map then
					_fsm:To("WinCondition")
					return
				end

				broadcast("ActiveRound", map.Id)
				notify("Round started! Robbers: steal the loot and extract. SPECops: stop them!", "Info")

				_roundTimer = map.RoundDuration
				ProgressionService.StartRound()
				CombatService.StartRound()
				AbilityService.StartRound()
				LootService.StartRound(map)

				-- Wire kill/loot events to progression (stored so OnExit can clean up)
				_roundConnections = {}
				_roundConnections[1] = CombatService.PlayerKilled:Connect(function(killer, _victim, _weapon)
					ProgressionService.RecordKill(killer)
				end)
				_roundConnections[2] = LootService.LootPickedUp:Connect(function(player, _itemId, value)
					ProgressionService.RecordLoot(player, value)
				end)
				_roundConnections[3] = LootService.ExtractionComplete:Connect(function(player, value)
					ProgressionService.RecordExtraction(player, value)
				end)

				-- Round timer countdown
				_timerThread = task.spawn(function()
					while _roundTimer > 0 do
						broadcastTimer(_roundTimer)
						task.wait(1)
						_roundTimer -= 1
					end
					broadcastTimer(0)
				end)

				-- Win condition evaluator
				_winEvalThread = task.spawn(function()
					while true do
						task.wait(Constants.TIMING.WIN_EVAL_INTERVAL)
						local result = evaluateWinConditions()
						if result then
							_winResult = result
							_fsm:To("WinCondition")
							return
						end
					end
				end)
			end,
			OnExit = function(_next)
				cancelThread(_timerThread)
				cancelThread(_winEvalThread)
				_timerThread = nil
				_winEvalThread = nil
				for _, conn in _roundConnections do
					conn:Disconnect()
				end
				_roundConnections = {}
			end,
		},

		WinCondition = {
			Transitions = { "Rewards" },
			OnEnter = function(_prev)
				local result = _winResult or { WinningTeam = "SPECops", Reason = "TimerExpired" }

				CombatService.EndRound()
				AbilityService.EndRound()
				LootService.EndRound()

				NetworkService.FireAllClients(Constants.NETWORK.WIN_CONDITION_RESULT, {
					WinningTeam = result.WinningTeam,
					WinReason = result.Reason,
					ExtractedValue = LootService.GetExtractedTotal(),
				})

				notify(result.WinningTeam .. " win! (" .. result.Reason .. ")", "Info")

				task.spawn(function()
					task.wait(Constants.TIMING.WIN_CONDITION_DISPLAY)
					_fsm:To("Rewards")
				end)
			end,
		},

		Rewards = {
			Transitions = { "Cleanup" },
			OnEnter = function(_prev)
				broadcast("Rewards")

				local winResult = _winResult or { WinningTeam = "SPECops", Reason = "TimerExpired" }
				local summary: RoundSummary = {
					WinningTeam = winResult.WinningTeam :: any,
					WinReason = winResult.Reason :: any,
					Duration = (_currentMap and _currentMap.RoundDuration or 0) - _roundTimer,
					LootExtracted = LootService.GetExtractedTotal(),
					TopPlayers = {},
				}

				ProgressionService.FinaliseRound(summary)
				RoundService.RoundEnded:Fire(summary)

				task.spawn(function()
					task.wait(Constants.TIMING.REWARDS_DISPLAY)
					_fsm:To("Cleanup")
				end)
			end,
		},

		Cleanup = {
			Transitions = { "Lobby" },
			OnEnter = function(_prev)
				broadcast("Cleanup")
				_winResult = nil
				_roundTimer = 0

				task.spawn(function()
					task.wait(Constants.TIMING.CLEANUP_DURATION)
					MapService.UnloadMap()
					_currentMap = nil
					_fsm:To("Lobby")
				end)
			end,
		},
	})
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RoundService.Init()
	_fsm = buildFSM()

	_fsm.StateChanged:Connect(function(newState, prevState)
		print(("[RoundService] %s → %s"):format(prevState, newState))
	end)

	-- Handle players joining mid-round
	Players.PlayerAdded:Connect(function(player)
		local state = _fsm.State
		NetworkService.FireClient(Constants.NETWORK.ROUND_STATE_CHANGED, player, state)
		if state == "ActiveRound" then
			NetworkService.FireClient(Constants.NETWORK.ROUND_TIMER_SYNC, player, _roundTimer)
		end
	end)
end

function RoundService.Start()
	-- Kick off the FSM from Lobby (it self-transitions via player count)
	broadcast("Lobby")
end

function RoundService.GetState(): string
	return _fsm.State
end

function RoundService.GetCurrentMap(): MapConfig?
	return _currentMap
end

function RoundService.GetRoundTimer(): number
	return _roundTimer
end

-- Force-end the round (admin command use)
function RoundService.ForceEnd(reason: string?)
	if _fsm.State == "ActiveRound" then
		_winResult = { WinningTeam = "SPECops", Reason = reason or "AdminForceEnd" }
		_fsm:To("WinCondition")
	end
end

return RoundService
