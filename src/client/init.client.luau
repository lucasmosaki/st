--!strict
-- Client bootstrap: initialises all controllers in dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for server to create remotes before initialising anything
ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Controllers

local RoundController = require(Controllers.RoundController)
local CombatController = require(Controllers.CombatController)
local AbilityController = require(Controllers.AbilityController)
local LootController = require(Controllers.LootController)
local HUDController = require(Controllers.HUDController)

-- ── Initialise ────────────────────────────────────────────────────────────────

RoundController.Init()
CombatController.Init()
AbilityController.Init()
LootController.Init()

-- HUDController gets references so it can wire up signals without circular deps
HUDController.Init(CombatController, LootController, RoundController, AbilityController)

-- ── Equip starting loadout when team is assigned ──────────────────────────────

RoundController.TeamAssigned:Connect(function(teamName: string)
	local loadout: { PrimaryWeapon: string, ActiveAbility: string }

	if teamName == "Robbers" then
		loadout = { PrimaryWeapon = "AK74", ActiveAbility = "SmokeBomb" }
	else
		loadout = { PrimaryWeapon = "M4A1", ActiveAbility = "Flashbang" }
	end

	CombatController.Equip(loadout.PrimaryWeapon)
	AbilityController.SetEquippedAbility(loadout.ActiveAbility)
end)

-- Unequip on round end
RoundController.StateChanged:Connect(function(state: string, _data: any)
	if state == "Cleanup" or state == "Lobby" then
		CombatController.Unequip()
		AbilityController.SetEquippedAbility(nil)
	end
end)

print("[Client] SPECops vs Robbers — client initialised.")
