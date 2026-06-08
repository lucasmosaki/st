--!strict
-- SPECops ability data definitions.
-- SPECops are individually weaker but excel through information and coordination.

local Types = require(script.Parent.Parent.Types)

type AbilityData = Types.AbilityData

local SPECopsAbilities: { [string]: AbilityData } = {

	-- ── Passive Abilities ─────────────────────────────────────────────────────

	TacticalTraining = {
		Id = "TacticalTraining",
		Name = "Tactical Training",
		Description = "Reduce your weapon recoil, improving accuracy in sustained fire.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	FastReload = {
		Id = "FastReload",
		Name = "Fast Reload",
		Description = "Reload your weapons faster, reducing downtime in combat.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	Ironclad = {
		Id = "Ironclad",
		Name = "Ironclad",
		Description = "Take slightly reduced damage from all sources, improving your survivability.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	-- ── Active Abilities ──────────────────────────────────────────────────────

	Flashbang = {
		Id = "Flashbang",
		Name = "Flashbang",
		Description = "Throw a flashbang that blinds and disorients all players in a 30-stud radius for 4 seconds.",
		ActivationType = "Active",
		Cooldown = 25,
		Charges = 2,
		Duration = 4,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	SensorDart = {
		Id = "SensorDart",
		Name = "Sensor Dart",
		Description = "Fire a sensor dart that reveals all Robbers within 50 studs for 20 seconds.",
		ActivationType = "Active",
		Cooldown = 35,
		Charges = 1,
		Duration = 20,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	PortableShield = {
		Id = "PortableShield",
		Name = "Portable Shield",
		Description = "Deploy a ballistic shield that absorbs up to 200 damage before breaking.",
		ActivationType = "Active",
		Cooldown = 50,
		Charges = 1,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	UAVScan = {
		Id = "UAVScan",
		Name = "UAV Scan",
		Description = "Launch a UAV that scans a 200-stud radius, pinging all Robbers on the minimap for 15 seconds.",
		ActivationType = "Active",
		Cooldown = 55,
		Charges = 1,
		Duration = 15,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},

	StunGrenade = {
		Id = "StunGrenade",
		Name = "Stun Grenade",
		Description = "Throw a grenade that slows and disrupts Robbers in a radius, impeding their escape.",
		ActivationType = "Active",
		Cooldown = 30,
		Charges = 2,
		Duration = 5,
		Icon = "rbxassetid://0",
		Team = "SPECops",
	},
}

return SPECopsAbilities
