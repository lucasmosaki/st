--!strict
-- MapRegistry: self-registration pattern for maps.
-- Maps call MapRegistry.Register() at module load time.
-- No game code needs to be modified when adding a new map.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

type MapConfig = Types.MapConfig

local MapRegistry = {}

local _maps: { [string]: MapConfig } = {}
local _geometryBuilders: { [string]: (MapConfig) -> Model } = {}

function MapRegistry.Register(config: MapConfig)
	assert(config.Id and config.Id ~= "", "[MapRegistry] Map must have an Id")
	assert(not _maps[config.Id], "[MapRegistry] Duplicate map Id: " .. config.Id)
	_maps[config.Id] = config
	print("[MapRegistry] Registered map:", config.DisplayName)
end

function MapRegistry.GetMap(id: string): MapConfig?
	return _maps[id]
end

function MapRegistry.GetAll(): { MapConfig }
	local list: { MapConfig } = {}
	for _, cfg in _maps do
		list[#list + 1] = cfg
	end
	return list
end

function MapRegistry.GetEligible(playerCount: number): { MapConfig }
	local list: { MapConfig } = {}
	for _, cfg in _maps do
		if playerCount >= cfg.MinPlayers and playerCount <= cfg.MaxPlayers then
			list[#list + 1] = cfg
		end
	end
	return list
end

function MapRegistry.RegisterGeometry(mapId: string, buildFn: (MapConfig) -> Model)
	_geometryBuilders[mapId] = buildFn
end

function MapRegistry.GetGeometryBuilder(mapId: string): ((MapConfig) -> Model)?
	return _geometryBuilders[mapId]
end

-- Auto-load all map modules in the Maps folder so they self-register
function MapRegistry.LoadAll(mapsFolder: Folder)
	for _, child in mapsFolder:GetChildren() do
		if child:IsA("ModuleScript") and child.Name ~= "MapRegistry" then
			local ok, err = pcall(require, child)
			if not ok then
				warn("[MapRegistry] Failed to load map module:", child.Name, err)
			end
		end
	end
end

return MapRegistry
