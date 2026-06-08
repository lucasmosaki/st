--!strict
-- Loot item registry.  Each entry is a pickable item with value and bag weight.
-- Maps reference item IDs from their LootNodeConfig.LootPool arrays.

local Types = require(script.Parent.Parent.Types)

type LootItemData = Types.LootItemData

local LootData: { [string]: LootItemData } = {

	CashBundle = {
		Id = "CashBundle",
		Name = "CashBundle",
		DisplayName = "Cash Bundle",
		Value = 10,
		Weight = 5,
		InteractionTime = 1.5,
	},

	GoldBar = {
		Id = "GoldBar",
		Name = "GoldBar",
		DisplayName = "Gold Bar",
		Value = 25,
		Weight = 15,
		InteractionTime = 2.5,
	},

	Painting = {
		Id = "Painting",
		Name = "Painting",
		DisplayName = "Stolen Painting",
		Value = 30,
		Weight = 20,
		InteractionTime = 3.0,
	},

	Diamond = {
		Id = "Diamond",
		Name = "Diamond",
		DisplayName = "Diamond",
		Value = 50,
		Weight = 5,
		InteractionTime = 2.0,
	},

	Jewelry = {
		Id = "Jewelry",
		Name = "Jewelry",
		DisplayName = "Jewelry Set",
		Value = 20,
		Weight = 8,
		InteractionTime = 1.8,
	},

	ArtifactVase = {
		Id = "ArtifactVase",
		Name = "ArtifactVase",
		DisplayName = "Ancient Vase",
		Value = 40,
		Weight = 25,
		InteractionTime = 4.0,
	},

	CasinoChips = {
		Id = "CasinoChips",
		Name = "CasinoChips",
		DisplayName = "Casino Chips",
		Value = 15,
		Weight = 6,
		InteractionTime = 1.2,
	},

	ServerData = {
		Id = "ServerData",
		Name = "ServerData",
		DisplayName = "Encrypted Drive",
		Value = 45,
		Weight = 3,
		InteractionTime = 5.0,
	},
}

-- Helper: compute the total possible value of a loot pool
function LootData.PoolTotalValue(pool: { string }, maxItems: number): number
	local total = 0
	local count = 0
	for _, id in pool do
		if count >= maxItems then
			break
		end
		local item = LootData[id]
		if item then
			total += item.Value
			count += 1
		end
	end
	return total
end

return LootData
