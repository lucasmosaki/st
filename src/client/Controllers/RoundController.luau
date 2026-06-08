--!strict
-- RoundController: receives round state changes and timer syncs, drives round UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- ── RoundController ───────────────────────────────────────────────────────────

local RoundController = {}

RoundController.StateChanged = Signal.new() :: Signal.Signal<string, any>
RoundController.TimerUpdated = Signal.new() :: Signal.Signal<number>
RoundController.TeamAssigned = Signal.new() :: Signal.Signal<string>
RoundController.WinConditionResult = Signal.new() :: Signal.Signal<{any}>
RoundController.MapVoteState = Signal.new() :: Signal.Signal<{any}, {any}>
RoundController.NotificationReceived = Signal.new() :: Signal.Signal<{any}>
RoundController.ScoreboardUpdated = Signal.new() :: Signal.Signal<{any}>
RoundController.RewardsSummary = Signal.new() :: Signal.Signal<{any}>
RoundController.ProfileSynced = Signal.new() :: Signal.Signal<{any}>

local _currentState: string = "Lobby"
local _currentTeam: string = "Lobby"
local _roundTimer: number = 0

function RoundController.Init()
	-- Round state changes
	getRemote(Constants.NETWORK.ROUND_STATE_CHANGED).OnClientEvent:Connect(
		function(newState: string, data: any)
			_currentState = newState
			RoundController.StateChanged:Fire(newState, data)
		end
	)

	-- Timer sync
	getRemote(Constants.NETWORK.ROUND_TIMER_SYNC).OnClientEvent:Connect(function(remaining: number)
		_roundTimer = remaining
		RoundController.TimerUpdated:Fire(remaining)
	end)

	-- Team assignment
	getRemote(Constants.NETWORK.TEAM_ASSIGNED).OnClientEvent:Connect(function(teamName: string)
		_currentTeam = teamName
		RoundController.TeamAssigned:Fire(teamName)
	end)

	-- Win condition
	getRemote(Constants.NETWORK.WIN_CONDITION_RESULT).OnClientEvent:Connect(function(data)
		RoundController.WinConditionResult:Fire(data)
	end)

	-- Map vote state
	getRemote(Constants.NETWORK.MAP_VOTE_STATE).OnClientEvent:Connect(function(candidates, tally)
		RoundController.MapVoteState:Fire(candidates, tally)
	end)

	-- Notifications
	getRemote(Constants.NETWORK.NOTIFICATION).OnClientEvent:Connect(function(data)
		RoundController.NotificationReceived:Fire(data)
	end)

	-- Scoreboard
	getRemote(Constants.NETWORK.SCOREBOARD_UPDATE).OnClientEvent:Connect(function(data)
		RoundController.ScoreboardUpdated:Fire(data)
	end)

	-- Rewards
	getRemote(Constants.NETWORK.REWARDS_SUMMARY).OnClientEvent:Connect(function(data)
		RoundController.RewardsSummary:Fire(data)
	end)

	-- Profile sync
	getRemote(Constants.NETWORK.PROFILE_SYNC).OnClientEvent:Connect(function(data)
		RoundController.ProfileSynced:Fire(data)
	end)
end

-- Cast a map vote
function RoundController.CastMapVote(mapId: string)
	if _currentState ~= "MapVoting" then return end
	getRemote(Constants.NETWORK.MAP_VOTE_CAST):FireServer(mapId)
end

function RoundController.GetState(): string
	return _currentState
end

function RoundController.GetTeam(): string
	return _currentTeam
end

function RoundController.GetTimer(): number
	return _roundTimer
end

function RoundController.FormatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

return RoundController
