--!strict
-- TestMap: the default development map.
-- Demonstrates the full map config schema.
-- Replace spawn CFrames and loot nodes with actual in-world positions.

local MapRegistry = require(script.Parent.MapRegistry)

MapRegistry.Register({
	Id = "TestMap",
	DisplayName = "Downtown Heist",
	MinPlayers = 2,
	MaxPlayers = 20,
	RoundDuration = 480,
	PreparationDuration = 30,

	-- Robbers spawn clustered near the heist objective
	RobberSpawns = {
		CFrame.new(-60, 5, 0),
		CFrame.new(-65, 5, 5),
		CFrame.new(-65, 5, -5),
		CFrame.new(-70, 5, 0),
		CFrame.new(-70, 5, 10),
	},

	-- SPECops spawn further away and spread out
	SPECopsSpawns = {
		CFrame.new(60, 5, -30),
		CFrame.new(65, 5, -25),
		CFrame.new(70, 5, -20),
		CFrame.new(75, 5, -15),
		CFrame.new(60, 5, 30),
		CFrame.new(65, 5, 25),
		CFrame.new(70, 5, 20),
		CFrame.new(75, 5, 15),
		CFrame.new(80, 5, 0),
		CFrame.new(85, 5, -5),
		CFrame.new(85, 5, 5),
		CFrame.new(90, 5, 0),
		CFrame.new(95, 5, -10),
		CFrame.new(95, 5, 10),
		CFrame.new(100, 5, 0),
	},

	-- Three distinct loot locations, each with different pools
	LootNodes = {
		-- Jewelry Store
		{
			Id = "JewelryStore_1",
			LocationName = "Jewelry Store",
			Position = Vector3.new(-20, 2, -15),
			LootPool = { "Diamond", "Jewelry", "CashBundle" },
			MaxItemsSpawned = 3,
			RespawnTime = 60,
		},
		{
			Id = "JewelryStore_2",
			LocationName = "Jewelry Store",
			Position = Vector3.new(-25, 2, -10),
			LootPool = { "Jewelry", "CashBundle", "Diamond" },
			MaxItemsSpawned = 2,
			RespawnTime = 60,
		},
		{
			Id = "JewelryStore_3",
			LocationName = "Jewelry Store",
			Position = Vector3.new(-15, 2, -20),
			LootPool = { "CashBundle", "Jewelry" },
			MaxItemsSpawned = 3,
			RespawnTime = 45,
		},

		-- Museum
		{
			Id = "Museum_1",
			LocationName = "City Museum",
			Position = Vector3.new(0, 2, 30),
			LootPool = { "ArtifactVase", "Painting", "GoldBar" },
			MaxItemsSpawned = 2,
			RespawnTime = 90,
		},
		{
			Id = "Museum_2",
			LocationName = "City Museum",
			Position = Vector3.new(10, 2, 35),
			LootPool = { "Painting", "ArtifactVase" },
			MaxItemsSpawned = 2,
			RespawnTime = 90,
		},
		{
			Id = "Museum_3",
			LocationName = "City Museum",
			Position = Vector3.new(-10, 2, 25),
			LootPool = { "GoldBar", "Painting", "CashBundle" },
			MaxItemsSpawned = 3,
			RespawnTime = 75,
		},

		-- Tech Office
		{
			Id = "TechOffice_1",
			LocationName = "Tech Office",
			Position = Vector3.new(20, 2, -20),
			LootPool = { "ServerData", "CashBundle" },
			MaxItemsSpawned = 2,
			RespawnTime = 120,
		},
		{
			Id = "TechOffice_2",
			LocationName = "Tech Office",
			Position = Vector3.new(25, 2, -15),
			LootPool = { "ServerData" },
			MaxItemsSpawned = 1,
			RespawnTime = 120,
		},

		-- Casino
		{
			Id = "Casino_1",
			LocationName = "Casino Floor",
			Position = Vector3.new(5, 2, -5),
			LootPool = { "CasinoChips", "CashBundle", "Diamond" },
			MaxItemsSpawned = 4,
			RespawnTime = 40,
		},
		{
			Id = "Casino_2",
			LocationName = "Casino Floor",
			Position = Vector3.new(-5, 2, 5),
			LootPool = { "CasinoChips", "GoldBar" },
			MaxItemsSpawned = 3,
			RespawnTime = 40,
		},
	},

	-- Single extraction zone on the opposite side of the map from SPECops spawn
	ExtractionZones = {
		{ Position = Vector3.new(-100, 2, 0), Radius = 15 },
	},

	-- Total loot value used for win condition calculation (70% threshold)
	-- Jewelry(3*20+3*20+3*10=120) + Museum(2*40+2*30+3*25+3*30=280) + Tech(2*45+1*45=135) + Casino(4*15+4*10+3*15+3*25=240)
	-- Approximate total: ~775, 70% = ~542
	TotalLootValue = 775,

	Description = "A bustling downtown district with a jewelry store, museum, tech office, and casino.",
	ThumbnailId = "rbxassetid://0",
})
