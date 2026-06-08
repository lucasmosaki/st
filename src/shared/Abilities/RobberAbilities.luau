--!strict
-- Robber ability data definitions.
-- Robbers are individually stronger; their abilities reflect that power.

local Types = require(script.Parent.Parent.Types)

type AbilityData = Types.AbilityData

local RobberAbilities: { [string]: AbilityData } = {

	-- ── Passive Abilities ─────────────────────────────────────────────────────

	GhostWalker = {
		Id = "GhostWalker",
		Name = "Ghost Walker",
		Description = "Your footsteps are nearly silent, making it much harder for SPECops to hear you moving.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0", -- replace with real asset
		Team = "Robbers",
	},

	MasterThief = {
		Id = "MasterThief",
		Name = "Master Thief",
		Description = "Your looting speed is significantly increased.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	Smuggler = {
		Id = "Smuggler",
		Name = "Smuggler",
		Description = "Your bag capacity is increased by 30, allowing you to carry more valuable loot.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	IronSkin = {
		Id = "IronSkin",
		Name = "Iron Skin",
		Description = "Passively gain 25 bonus health, making you even harder to eliminate.",
		ActivationType = "Passive",
		Cooldown = 0,
		Charges = 0,
		Duration = 0,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	-- ── Active Abilities ──────────────────────────────────────────────────────

	SmokeBomb = {
		Id = "SmokeBomb",
		Name = "Smoke Bomb",
		Description = "Deploy a smoke grenade that creates a 10-second vision-blocking cloud, "
			.. "obscuring pursuit and covering extractions.",
		ActivationType = "Active",
		Cooldown = 30,
		Charges = 2,
		Duration = 10,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	AdrenalineRush = {
		Id = "AdrenalineRush",
		Name = "Adrenaline Rush",
		Description = "Inject combat stimulants for a burst of speed. Duration: 8 seconds.",
		ActivationType = "Active",
		Cooldown = 45,
		Charges = 1,
		Duration = 8,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	GrappleLauncher = {
		Id = "GrappleLauncher",
		Name = "Grapple Launcher",
		Description = "Fire a grapple hook at a surface to rapidly close distance or reach high ground.",
		ActivationType = "Active",
		Cooldown = 20,
		Charges = 1,
		Duration = 3,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	Hologram = {
		Id = "Hologram",
		Name = "Hologram",
		Description = "Project a decoy hologram of yourself at your current position to confuse SPECops.",
		ActivationType = "Active",
		Cooldown = 40,
		Charges = 1,
		Duration = 15,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},

	EmpDevice = {
		Id = "EmpDevice",
		Name = "EMP Device",
		Description = "Temporarily disable SPECops gadgets and UAV tracking in a medium radius.",
		ActivationType = "Active",
		Cooldown = 60,
		Charges = 1,
		Duration = 12,
		Icon = "rbxassetid://0",
		Team = "Robbers",
	},
}

return RobberAbilities
