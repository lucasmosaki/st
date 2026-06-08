--!strict
-- TeamService: team assignment with weighted-random Robber selection.
-- Implements the required balance ratio and prevents repeat-Robber runs.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DataService = require(script.Parent.DataService)
local NetworkService = require(script.Parent.NetworkService)

-- ── TeamService ───────────────────────────────────────────────────────────────

local TeamService = {}

local _robberTeam: Team
local _specopTeam: Team
local _lobbyTeam: Team

-- Track current round assignments
local _currentRobbers: { number } = {}    -- UserId list
local _currentSPECops: { number } = {}

local function ensureTeam(name: string, color: BrickColor): Team
	local existing = Teams:FindFirstChild(name) :: Team?
	if existing then
		return existing
	end
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

function TeamService.Init()
	_robberTeam = ensureTeam("Robbers", BrickColor.new("Bright red"))
	_specopTeam = ensureTeam("SPECops", BrickColor.new("Bright blue"))
	_lobbyTeam = ensureTeam("Lobby", BrickColor.new("Medium stone grey"))
end

-- Returns the desired number of Robbers for a given player count
function TeamService.CalculateRobberCount(playerCount: number): number
	return math.max(
		Constants.TEAM_BALANCE.MIN_ROBBERS,
		math.floor(playerCount * Constants.TEAM_BALANCE.ROBBER_RATIO)
	)
end

-- Weighted random selection of robberCount players from the pool
local function weightedSelect(pool: { Player }, robberCount: number): { Player }
	local weights: { number } = {}
	local totalWeight = 0

	for _, player in pool do
		local profile = DataService.GetProfile(player)
		local w = if profile then profile.RobberWeight else Constants.TEAM_BALANCE.ROBBER_WEIGHT_DEFAULT
		-- Players who were Robber last round get a significant penalty
		if profile and profile.LastRoleWasRobber then
			w = w * 0.1
		end
		w = math.max(0.01, w)
		weights[#weights + 1] = w
		totalWeight += w
	end

	local selected: { Player } = {}
	local available = { table.unpack(pool) }
	local availableWeights = { table.unpack(weights) }

	for _ = 1, math.min(robberCount, #pool) do
		local roll = math.random() * totalWeight
		local cumulative = 0
		local chosen = 1
		for idx, w in availableWeights do
			cumulative += w
			if roll <= cumulative then
				chosen = idx
				break
			end
		end

		selected[#selected + 1] = available[chosen]
		totalWeight -= availableWeights[chosen]
		table.remove(available, chosen)
		table.remove(availableWeights, chosen)
	end

	return selected
end

-- Assign teams for a new round and return { robbers, specops }
function TeamService.AssignTeams(): ({ Player }, { Player })
	local allPlayers = Players:GetPlayers()
	local robberCount = TeamService.CalculateRobberCount(#allPlayers)
	local robbers = weightedSelect(allPlayers, robberCount)

	local robberSet: { [Player]: boolean } = {}
	for _, p in robbers do
		robberSet[p] = true
	end

	local specops: { Player } = {}
	for _, p in allPlayers do
		if not robberSet[p] then
			specops[#specops + 1] = p
		end
	end

	-- Apply team assignments
	for _, player in robbers do
		player.Team = _robberTeam
		DataService.UpdateProfile(player, function(prof)
			prof.LastRoleWasRobber = true
			prof.RobberWeight = Constants.TEAM_BALANCE.ROBBER_WEIGHT_RESET
		end)
	end

	for _, player in specops do
		player.Team = _specopTeam
		DataService.UpdateProfile(player, function(prof)
			prof.LastRoleWasRobber = false
			prof.RobberWeight = math.min(
				Constants.TEAM_BALANCE.ROBBER_WEIGHT_MAX,
				(prof.RobberWeight or Constants.TEAM_BALANCE.ROBBER_WEIGHT_DEFAULT)
					+ Constants.TEAM_BALANCE.ROBBER_WEIGHT_INCREASE
			)
		end)
	end

	-- Cache for quick lookup
	_currentRobbers = {}
	for _, p in robbers do
		_currentRobbers[#_currentRobbers + 1] = p.UserId
	end
	_currentSPECops = {}
	for _, p in specops do
		_currentSPECops[#_currentSPECops + 1] = p.UserId
	end

	-- Notify clients
	for _, player in robbers do
		NetworkService.FireClient(Constants.NETWORK.TEAM_ASSIGNED, player, "Robbers")
	end
	for _, player in specops do
		NetworkService.FireClient(Constants.NETWORK.TEAM_ASSIGNED, player, "SPECops")
	end

	return robbers, specops
end

-- Move all players back to lobby team
function TeamService.ReturnToLobby()
	for _, player in Players:GetPlayers() do
		player.Team = _lobbyTeam
	end
	_currentRobbers = {}
	_currentSPECops = {}
end

function TeamService.GetTeamOf(player: Player): string
	if player.Team == _robberTeam then
		return "Robbers"
	elseif player.Team == _specopTeam then
		return "SPECops"
	end
	return "Lobby"
end

function TeamService.IsRobber(player: Player): boolean
	return player.Team == _robberTeam
end

function TeamService.IsSPECops(player: Player): boolean
	return player.Team == _specopTeam
end

function TeamService.GetRobbers(): { Player }
	local result: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Team == _robberTeam then
			result[#result + 1] = player
		end
	end
	return result
end

function TeamService.GetSPECops(): { Player }
	local result: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Team == _specopTeam then
			result[#result + 1] = player
		end
	end
	return result
end

function TeamService.GetRobberTeam(): Team
	return _robberTeam
end

function TeamService.GetSPECopsTeam(): Team
	return _specopTeam
end

function TeamService.GetLobbyTeam(): Team
	return _lobbyTeam
end

return TeamService
