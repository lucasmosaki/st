--!strict
-- MapService: handles map voting, loading, spawn placement, and cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local NetworkService = require(script.Parent.NetworkService)
local MapRegistry = require(script.Parent.Parent.Maps.MapRegistry)

type MapConfig = Types.MapConfig

-- ── MapService ────────────────────────────────────────────────────────────────

local MapService = {}

local _currentMap: MapConfig? = nil
local _votes: { [number]: string } = {}   -- UserId → MapId

function MapService.Init()
	-- Seed randomness once
	math.randomseed(os.time())

	-- Load all map module scripts so they self-register
	MapRegistry.LoadAll(script.Parent.Parent.Maps)

	-- Listen for client votes
	NetworkService.OnClientEvent(Constants.NETWORK.MAP_VOTE_CAST, function(player, mapId)
		if type(mapId) ~= "string" then
			return
		end
		local maps = MapRegistry.GetEligible(#Players:GetPlayers())
		for _, cfg in maps do
			if cfg.Id == mapId then
				_votes[player.UserId] = mapId
				MapService.BroadcastVoteState()
				return
			end
		end
	end)
end

-- Begin a voting period and return the winning map after duration
function MapService.RunVoting(duration: number): MapConfig
	local playerCount = #Players:GetPlayers()
	local eligible = MapRegistry.GetEligible(playerCount)

	if #eligible == 0 then
		-- Fall back to any registered map
		eligible = MapRegistry.GetAll()
	end
	if #eligible == 0 then
		error("[MapService] No maps registered")
	end

	_votes = {}

	-- Send candidate list to clients
	local candidates: { { Id: string, DisplayName: string, Description: string } } = {}
	for _, cfg in eligible do
		candidates[#candidates + 1] = {
			Id = cfg.Id,
			DisplayName = cfg.DisplayName,
			Description = cfg.Description,
		}
	end
	NetworkService.FireAllClients(Constants.NETWORK.MAP_VOTE_STATE, candidates, duration)

	task.wait(duration)

	return MapService.TallyVotes(eligible)
end

function MapService.TallyVotes(eligible: { MapConfig }): MapConfig
	-- Count votes per map
	local tally: { [string]: number } = {}
	for _, cfg in eligible do
		tally[cfg.Id] = 0
	end
	for _, mapId in _votes do
		if tally[mapId] ~= nil then
			tally[mapId] += 1
		end
	end

	-- Find winner; ties broken randomly
	local winnerCfg: MapConfig = eligible[math.random(1, #eligible)]
	local maxVotes = -1
	for id, count in tally do
		if count > maxVotes then
			maxVotes = count
			for _, cfg in eligible do
				if cfg.Id == id then
					winnerCfg = cfg
					break
				end
			end
		end
	end

	_votes = {}
	return winnerCfg
end

function MapService.BroadcastVoteState()
	local playerCount = #Players:GetPlayers()
	local eligible = MapRegistry.GetEligible(playerCount)
	local tally: { [string]: number } = {}
	for _, mapId in _votes do
		tally[mapId] = (tally[mapId] or 0) + 1
	end
	NetworkService.FireAllClients(Constants.NETWORK.MAP_VOTE_STATE, eligible, tally)
end

-- Load a map into Workspace.
-- Priority 1: procedural geometry builder registered via MapRegistry.RegisterGeometry.
-- Priority 2: a Model in ServerStorage.Maps matching config.Id.
function MapService.LoadMap(config: MapConfig): boolean
	_currentMap = config
	NetworkService.FireAllClients(Constants.NETWORK.ROUND_STATE_CHANGED, "MapLoading", config.Id)

	local buildFn = MapRegistry.GetGeometryBuilder(config.Id)
	if buildFn then
		buildFn(config)
	else
		local ss = game:GetService("ServerStorage")
		local mapsFolder = ss:FindFirstChild("Maps")
		if mapsFolder then
			local model = mapsFolder:FindFirstChild(config.Id)
			if model then
				(model :: Instance):Clone().Parent = workspace
			end
		end
	end

	print("[MapService] Loaded map:", config.DisplayName)
	return true
end

-- Unload current map from Workspace
function MapService.UnloadMap()
	if not _currentMap then
		return
	end
	local mapFolder = workspace:FindFirstChild(_currentMap.Id)
	if mapFolder then
		mapFolder:Destroy()
	end
	print("[MapService] Unloaded map:", _currentMap.DisplayName)
	_currentMap = nil
end

-- Teleport a player to a spawn point for their team
function MapService.SpawnPlayer(player: Player, teamName: string)
	local config = _currentMap
	if not config then
		return
	end

	local spawns: { CFrame }
	if teamName == "Robbers" then
		spawns = config.RobberSpawns
	else
		spawns = config.SPECopsSpawns
	end

	if #spawns == 0 then
		return
	end

	local spawnCF = spawns[math.random(1, #spawns)]
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = spawnCF + Vector3.new(0, 3, 0)
	end
end

function MapService.GetCurrentMap(): MapConfig?
	return _currentMap
end

function MapService.GetExtractionZones(): { { Position: Vector3, Radius: number } }
	if not _currentMap then
		return {}
	end
	return _currentMap.ExtractionZones
end

return MapService
