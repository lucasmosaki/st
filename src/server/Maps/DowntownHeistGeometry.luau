--!strict
-- DowntownHeistGeometry: procedurally builds the Downtown Heist map.
-- Registered with MapRegistry so MapService calls it during LoadMap.
-- Produces 4 buildings, loot markers, extraction zone, and spawn pads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
type MapConfig = Types.MapConfig

-- ── Tuning ────────────────────────────────────────────────────────────────────

local WALL_H  = 12    -- wall height in studs
local WALL_T  = 1.2   -- wall thickness
local DOOR_W  = 7     -- door gap width
local DOOR_H  = 9     -- door opening height
local FLOOR_Y = 0.5   -- floor center Y; baseplate top sits at Y=0

local WALL_CENTER_Y = 1 + WALL_H / 2         -- = 7
local HEADER_Y      = 1 + DOOR_H + (WALL_H - DOOR_H) / 2  -- = 11.5

-- ── Primitive helpers ─────────────────────────────────────────────────────────

local function brickPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean,
	transparency: number
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = canCollide
	p.CastShadow = canCollide
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function addBillboard(host: BasePart, text: string, color: Color3, widthPx: number, yOff: number)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(widthPx, 30)
	bg.StudsOffset = Vector3.new(0, yOff, 0)
	bg.AlwaysOnTop = false
	bg.Parent = host

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.Parent = bg
end

-- ── Building constructor ──────────────────────────────────────────────────────
--
-- Builds a box building: floor + 4 walls, one of which has a door opening.
-- doorWall: which face gets the door.
--   "N" = north face (minZ side)   "S" = south face (maxZ side)
--   "E" = east face  (maxX side)   "W" = west face  (minX side)

local function buildBuilding(
	root: Instance,
	name: string,
	minX: number, maxX: number,
	minZ: number, maxZ: number,
	floorColor: Color3,
	wallColor: Color3,
	doorWall: string
)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root

	local cx = (minX + maxX) / 2
	local cz = (minZ + maxZ) / 2
	local sx = maxX - minX
	local sz = maxZ - minZ

	-- Floor
	brickPart(folder, "Floor",
		Vector3.new(sx, 1, sz),
		CFrame.new(cx, FLOOR_Y, cz),
		floorColor, Enum.Material.SmoothPlastic, true, 0)

	-- Helpers closed over folder and wallColor
	local function solidWall(wName: string, size: Vector3, x: number, z: number)
		brickPart(folder, wName, size,
			CFrame.new(x, WALL_CENTER_Y, z),
			wallColor, Enum.Material.SmoothPlastic, true, 0)
	end

	-- Splits a wall into: left slab, right slab, and a header above the door.
	-- alongX=true  → wall runs along X axis (N/S walls), door gap in X direction.
	-- alongX=false → wall runs along Z axis (E/W walls), door gap in Z direction.
	local function wallWithDoor(
		wName: string,
		wallLen: number,
		wallThk: number,
		cx2: number,
		cz2: number,
		alongX: boolean
	)
		local sideLen = (wallLen - DOOR_W) / 2
		local halfD   = DOOR_W / 2

		if alongX then
			solidWall(wName .. "L",
				Vector3.new(sideLen, WALL_H, wallThk),
				cx2 - halfD - sideLen / 2, cz2)
			solidWall(wName .. "R",
				Vector3.new(sideLen, WALL_H, wallThk),
				cx2 + halfD + sideLen / 2, cz2)
			brickPart(folder, wName .. "H",
				Vector3.new(DOOR_W, WALL_H - DOOR_H, wallThk),
				CFrame.new(cx2, HEADER_Y, cz2),
				wallColor, Enum.Material.SmoothPlastic, true, 0)
		else
			solidWall(wName .. "L",
				Vector3.new(wallThk, WALL_H, sideLen),
				cx2, cz2 - halfD - sideLen / 2)
			solidWall(wName .. "R",
				Vector3.new(wallThk, WALL_H, sideLen),
				cx2, cz2 + halfD + sideLen / 2)
			brickPart(folder, wName .. "H",
				Vector3.new(wallThk, WALL_H - DOOR_H, DOOR_W),
				CFrame.new(cx2, HEADER_Y, cz2),
				wallColor, Enum.Material.SmoothPlastic, true, 0)
		end
	end

	-- Wall extents: walls wrap just outside the floor footprint.
	-- N/S walls get WALL_T*2 extra length to cover the E/W corner thickness.
	local fullW  = sx + WALL_T * 2
	local northZ = minZ - WALL_T / 2
	local southZ = maxZ + WALL_T / 2
	local eastX  = maxX + WALL_T / 2
	local westX  = minX - WALL_T / 2

	if doorWall == "N" then
		wallWithDoor("WallN", fullW, WALL_T, cx, northZ, true)
	else
		solidWall("WallN", Vector3.new(fullW, WALL_H, WALL_T), cx, northZ)
	end

	if doorWall == "S" then
		wallWithDoor("WallS", fullW, WALL_T, cx, southZ, true)
	else
		solidWall("WallS", Vector3.new(fullW, WALL_H, WALL_T), cx, southZ)
	end

	if doorWall == "E" then
		wallWithDoor("WallE", sz, WALL_T, eastX, cz, false)
	else
		solidWall("WallE", Vector3.new(WALL_T, WALL_H, sz), eastX, cz)
	end

	if doorWall == "W" then
		wallWithDoor("WallW", sz, WALL_T, westX, cz, false)
	else
		solidWall("WallW", Vector3.new(WALL_T, WALL_H, sz), westX, cz)
	end
end

-- ── Loot markers ─────────────────────────────────────────────────────────────

local function lootMarker(root: Instance, pos: Vector3, locationName: string)
	local p = brickPart(root, "LootMarker",
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(pos),
		Color3.fromRGB(255, 200, 0),
		Enum.Material.Neon,
		false, 0)
	addBillboard(p, locationName, Color3.fromRGB(255, 220, 0), 140, 2.5)
end

-- ── Extraction zone ───────────────────────────────────────────────────────────

local function buildExtractionZone(root: Instance, pos: Vector3, radius: number)
	local disc = brickPart(root, "ExtractionDisc",
		Vector3.new(radius * 2, 0.3, radius * 2),
		CFrame.new(pos.X, 0.55, pos.Z),
		Color3.fromRGB(255, 215, 0),
		Enum.Material.Neon,
		false, 0.35)
	addBillboard(disc, "EXTRACTION ZONE", Color3.fromRGB(255, 215, 0), 200, 7)

	-- Eight neon posts ringing the perimeter
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		brickPart(root, "ExtPost",
			Vector3.new(0.5, 5, 0.5),
			CFrame.new(pos.X + math.cos(a) * radius, 2.5, pos.Z + math.sin(a) * radius),
			Color3.fromRGB(255, 215, 0),
			Enum.Material.Neon,
			true, 0.15)
	end
end

-- ── Spawn pads ────────────────────────────────────────────────────────────────

local function spawnPad(root: Instance, cf: CFrame, color: Color3, label: string)
	local p = brickPart(root, "SpawnPad",
		Vector3.new(4, 0.2, 4),
		CFrame.new(cf.Position.X, 0.25, cf.Position.Z),
		color, Enum.Material.Neon,
		false, 0.45)
	addBillboard(p, label, color, 80, 1.5)
end

-- ── Main builder ──────────────────────────────────────────────────────────────

local DowntownHeistGeometry = {}

function DowntownHeistGeometry.Build(mapConfig: MapConfig): Model
	local root = Instance.new("Model")
	root.Name = mapConfig.Id   -- "TestMap" — MapService.UnloadMap finds it by this name
	root.Parent = workspace

	-- ── Buildings ────────────────────────────────────────────────────────────
	-- All loot node positions are confirmed to be inside their respective building.
	-- Door directions face toward the open street that players approach from.

	-- Jewelry Store: nodes ~(-20,-15), (-25,-10), (-15,-20). Door east → toward Casino
	buildBuilding(root, "JewelryStore",
		-30, -12, -26, -6,
		Color3.fromRGB(245, 210, 210), Color3.fromRGB(200, 160, 160), "E")

	-- Casino Floor: nodes ~(5,-5), (-5,5). Door west → Robbers approach from X<0
	buildBuilding(root, "Casino",
		-8, 16, -14, 8,
		Color3.fromRGB(230, 215, 170), Color3.fromRGB(195, 165, 100), "W")

	-- Tech Office: nodes ~(20,-20), (25,-15). Door west → robbers enter from left
	buildBuilding(root, "TechOffice",
		18, 34, -28, -8,
		Color3.fromRGB(200, 225, 210), Color3.fromRGB(160, 195, 175), "W")

	-- City Museum: nodes ~(0,30), (10,35), (-10,25). Door south → central street
	buildBuilding(root, "CityMuseum",
		-18, 18, 18, 46,
		Color3.fromRGB(205, 205, 235), Color3.fromRGB(160, 160, 210), "S")

	-- ── Loot node markers ────────────────────────────────────────────────────
	for _, node in ipairs(mapConfig.LootNodes) do
		lootMarker(root, node.Position, node.LocationName)
	end

	-- ── Extraction zones ─────────────────────────────────────────────────────
	for _, zone in ipairs(mapConfig.ExtractionZones) do
		buildExtractionZone(root, zone.Position, zone.Radius)
	end

	-- ── Spawn pads ───────────────────────────────────────────────────────────
	for i, cf in ipairs(mapConfig.RobberSpawns) do
		spawnPad(root, cf, Color3.fromRGB(255, 80, 80), "Robber " .. i)
	end
	for i, cf in ipairs(mapConfig.SPECopsSpawns) do
		spawnPad(root, cf, Color3.fromRGB(80, 140, 255), "SPECops " .. i)
	end

	return root
end

return DowntownHeistGeometry
