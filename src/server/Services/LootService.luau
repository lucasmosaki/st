--!strict
-- LootService: manages loot nodes, bag state, and extraction logic.
-- All loot state is server-authoritative; clients only display what the server
-- broadcasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local LootDataModule = require(ReplicatedStorage.Shared.Loot.LootData)
local NetworkService = require(script.Parent.NetworkService)
local TeamService = require(script.Parent.TeamService)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

type LootNodeConfig = Types.LootNodeConfig
type LootNodeState = Types.LootNodeState
type BagState = Types.BagState
type MapConfig = Types.MapConfig

-- ── LootService ───────────────────────────────────────────────────────────────

local LootService = {}

LootService.LootPickedUp = Signal.new() :: Signal.Signal<Player, string, number>
LootService.ExtractionComplete = Signal.new() :: Signal.Signal<Player, number>

-- Node states (server-side)
local _nodes: { [string]: LootNodeState } = {}

-- Bag states per player
local _bags: { [number]: BagState } = {}   -- UserId → bag

-- Active interactions: UserId → { nodeId, startTime, connection }
local _interactions: { [number]: { nodeId: string, thread: thread? } } = {}

-- Extraction state per zone
local _extractionProgress: { [number]: { userId: number?, progress: number, thread: thread? } } = {}

-- Running loot steal totals
local _teamLootTotal: number = 0
local _extractedLootTotal: number = 0
local _roundActive: boolean = false
local _currentMapConfig: MapConfig? = nil

-- Passive bonuses applied from AbilityService
local _masterThiefPlayers: { [number]: boolean } = {}   -- UserId → active
local _smugglerPlayers: { [number]: boolean } = {}

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function getBagCapacity(userId: number): number
	local base = Constants.LOOT.BAG_CAPACITY
	if _smugglerPlayers[userId] then
		base += Constants.ABILITIES.SMUGGLER_BAG_BONUS
	end
	return base
end

local function getStealMultiplier(userId: number): number
	if _masterThiefPlayers[userId] then
		return Constants.ABILITIES.MASTER_THIEF_STEAL_MULT
	end
	return 1.0
end

local function broadcastNodeState(nodeId: string)
	local node = _nodes[nodeId]
	if not node then return end
	NetworkService.FireAllClients(Constants.NETWORK.LOOT_NODE_STATE, node)
end

local function broadcastBagUpdate(player: Player)
	local bag = _bags[player.UserId]
	if not bag then return end
	NetworkService.FireClient(Constants.NETWORK.BAG_UPDATE, player, bag)
end

local function spawnNodeItems(node: LootNodeState, config: LootNodeConfig)
	node.Items = {}
	for i = 1, config.MaxItemsSpawned do
		local pool = config.LootPool
		if #pool == 0 then break end
		local itemId = pool[math.random(1, #pool)]
		node.Items[i] = { ItemId = itemId, Active = true }
	end
	node.RespawnAt = nil
	broadcastNodeState(node.Id)
end

local function scheduleRespawn(node: LootNodeState, config: LootNodeConfig, delay: number)
	node.RespawnAt = os.time() + delay
	task.delay(delay, function()
		if not _roundActive then return end
		spawnNodeItems(node, config)
	end)
end

local function getCharacterPosition(player: Player): Vector3?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if hrp then hrp.Position else nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LootService.Init()
	NetworkService.OnClientEvent(Constants.NETWORK.INTERACT_LOOT, function(player, nodeId)
		LootService.StartInteraction(player, nodeId)
	end)

	NetworkService.OnClientEvent(Constants.NETWORK.REQUEST_EXTRACTION, function(player, zoneIndex)
		LootService.StartExtraction(player, zoneIndex)
	end)
end

function LootService.StartRound(mapConfig: MapConfig)
	_currentMapConfig = mapConfig
	_roundActive = true
	_nodes = {}
	_bags = {}
	_interactions = {}
	_extractionProgress = {}
	_teamLootTotal = 0
	_extractedLootTotal = 0
	_masterThiefPlayers = {}
	_smugglerPlayers = {}

	-- Initialise bags for all players
	for _, player in Players:GetPlayers() do
		_bags[player.UserId] = {
			CurrentWeight = 0,
			MaxWeight = getBagCapacity(player.UserId),
			Items = {},
		}
		broadcastBagUpdate(player)
	end

	-- Spawn loot nodes
	for _, cfg in mapConfig.LootNodes do
		local node: LootNodeState = {
			Id = cfg.Id,
			LocationName = cfg.LocationName,
			Position = cfg.Position,
			Items = {},
			RespawnAt = nil,
		}
		_nodes[cfg.Id] = node
		spawnNodeItems(node, cfg)
	end

	-- Initialise extraction zones
	for i = 1, #mapConfig.ExtractionZones do
		_extractionProgress[i] = { userId = nil, progress = 0, thread = nil }
	end

	-- Notify extraction zones exist
	NetworkService.FireAllClients(
		Constants.NETWORK.EXTRACTION_ZONE_ACTIVATED,
		mapConfig.ExtractionZones
	)
end

function LootService.EndRound()
	_roundActive = false
	-- Cancel all active interactions
	for userId, data in _interactions do
		if data.thread then
			task.cancel(data.thread)
		end
		_interactions[userId] = nil
	end
	-- Cancel extractions
	for i, data in _extractionProgress do
		if data.thread then
			task.cancel(data.thread)
		end
		_extractionProgress[i] = { userId = nil, progress = 0, thread = nil }
	end
	_currentMapConfig = nil
end

-- Called by AbilityService when passive bonuses activate
function LootService.SetMasterThief(userId: number, active: boolean)
	_masterThiefPlayers[userId] = active
end

function LootService.SetSmuggler(userId: number, active: boolean)
	_smugglerPlayers[userId] = active
	-- Update bag capacity immediately
	local bag = _bags[userId]
	if bag then
		bag.MaxWeight = getBagCapacity(userId)
		local player = Players:GetPlayerByUserId(userId)
		if player then broadcastBagUpdate(player) end
	end
end

function LootService.StartInteraction(player: Player, nodeId: string)
	if not _roundActive then return end
	if not TeamService.IsRobber(player) then return end

	-- Cancel any existing interaction
	LootService.CancelInteraction(player)

	local node = _nodes[nodeId]
	if not node then return end

	-- Check distance
	local pos = getCharacterPosition(player)
	if not pos then return end
	if (pos - node.Position).Magnitude > Constants.LOOT.LOOT_INTERACT_DISTANCE then
		return
	end

	-- Find an active item in this node
	local itemIdx: number? = nil
	local itemId: string? = nil
	for idx, item in node.Items do
		if item.Active then
			itemIdx = idx
			itemId = item.ItemId
			break
		end
	end
	if not itemIdx or not itemId then return end

	local lootItem = LootDataModule[itemId]
	if not lootItem then return end

	local bag = _bags[player.UserId]
	if not bag then return end
	if bag.CurrentWeight + lootItem.Weight > bag.MaxWeight then
		NetworkService.FireClient(Constants.NETWORK.NOTIFICATION, player, {
			Type = "Warning",
			Message = "Bag is full! Extract or leave some loot.",
		})
		return
	end

	local stealTime = lootItem.InteractionTime / getStealMultiplier(player.UserId)

	_interactions[player.UserId] = { nodeId = nodeId, thread = nil }

	local thread = task.spawn(function()
		-- Tick progress to client
		local elapsed = 0
		local interval = 0.05
		while elapsed < stealTime do
			task.wait(interval)
			elapsed += interval

			-- Re-validate range each tick (prevents ghost-picking)
			local currentPos = getCharacterPosition(player)
			if not currentPos then
				LootService.CancelInteraction(player)
				return
			end
			if (currentPos - node.Position).Magnitude > Constants.LOOT.LOOT_INTERACT_DISTANCE then
				LootService.CancelInteraction(player)
				NetworkService.FireClient(Constants.NETWORK.LOOT_INTERACTION_PROGRESS, player, nodeId, 0)
				return
			end

			NetworkService.FireClient(
				Constants.NETWORK.LOOT_INTERACTION_PROGRESS,
				player,
				nodeId,
				elapsed / stealTime
			)
		end

		-- Award loot
		node.Items[itemIdx :: number].Active = false
		bag.CurrentWeight += lootItem.Weight
		bag.Items[#bag.Items + 1] = {
			ItemId = itemId :: string,
			Count = 1,
			Value = lootItem.Value,
		}
		_teamLootTotal += lootItem.Value
		_interactions[player.UserId] = nil

		broadcastBagUpdate(player)
		broadcastNodeState(nodeId)

		NetworkService.FireAllClients(Constants.NETWORK.LOOT_PICKED_UP, player.UserId, {
			ItemId = itemId,
			Value = lootItem.Value,
			NodeId = nodeId,
			LocationName = node.LocationName,
		})

		LootService.LootPickedUp:Fire(player, itemId :: string, lootItem.Value)

		-- Check if node is exhausted, schedule respawn
		local anyActive = false
		for _, item in node.Items do
			if item.Active then
				anyActive = true
				break
			end
		end
		if not anyActive then
			for _, cfg in (_currentMapConfig :: MapConfig).LootNodes do
				if cfg.Id == nodeId then
					scheduleRespawn(node, cfg, cfg.RespawnTime)
					break
				end
			end
		end
	end)

	_interactions[player.UserId] = { nodeId = nodeId, thread = thread }
end

function LootService.CancelInteraction(player: Player)
	local data = _interactions[player.UserId]
	if not data then return end
	if data.thread then
		task.cancel(data.thread)
	end
	_interactions[player.UserId] = nil
	NetworkService.FireClient(Constants.NETWORK.LOOT_INTERACTION_PROGRESS, player, data.nodeId, 0)
end

function LootService.StartExtraction(player: Player, zoneIndex: number)
	if not _roundActive then return end
	if not TeamService.IsRobber(player) then return end

	local mapConfig = _currentMapConfig
	if not mapConfig then return end

	local zones = mapConfig.ExtractionZones
	if not zones[zoneIndex] then return end

	local bag = _bags[player.UserId]
	if not bag or bag.CurrentWeight == 0 then
		NetworkService.FireClient(Constants.NETWORK.NOTIFICATION, player, {
			Type = "Warning",
			Message = "Your bag is empty. Steal some loot first!",
		})
		return
	end

	-- Check proximity to zone
	local pos = getCharacterPosition(player)
	if not pos then return end
	local zone = zones[zoneIndex]
	if (pos - zone.Position).Magnitude > zone.Radius then
		return
	end

	local zoneData = _extractionProgress[zoneIndex]
	if zoneData.userId then
		return  -- already being extracted
	end

	zoneData.userId = player.UserId
	zoneData.progress = 0

	local thread = task.spawn(function()
		local elapsed = 0
		local interval = 0.05
		local duration = Constants.LOOT.EXTRACTION_TIME

		NetworkService.FireAllClients(Constants.NETWORK.EXTRACTION_PROGRESS, {
			ZoneIndex = zoneIndex,
			Progress = 0,
			ExtractingUserId = player.UserId,
		})

		while elapsed < duration do
			task.wait(interval)
			elapsed += interval

			-- Validate still in zone
			local currentPos = getCharacterPosition(player)
			if not currentPos then
				zoneData.userId = nil
				zoneData.progress = 0
				NetworkService.FireAllClients(Constants.NETWORK.EXTRACTION_INTERRUPTED, zoneIndex)
				return
			end
			if (currentPos - zone.Position).Magnitude > Constants.LOOT.EXTRACTION_INTERRUPT_DISTANCE then
				zoneData.userId = nil
				zoneData.progress = 0
				NetworkService.FireAllClients(Constants.NETWORK.EXTRACTION_INTERRUPTED, zoneIndex)
				NetworkService.FireClient(Constants.NETWORK.NOTIFICATION, player, {
					Type = "Warning",
					Message = "Extraction cancelled — you left the zone!",
				})
				return
			end

			zoneData.progress = elapsed / duration
			NetworkService.FireAllClients(Constants.NETWORK.EXTRACTION_PROGRESS, {
				ZoneIndex = zoneIndex,
				Progress = zoneData.progress,
				ExtractingUserId = player.UserId,
			})
		end

		-- Extraction success
		local lootValue = 0
		for _, item in bag.Items do
			lootValue += item.Value * item.Count
		end
		_extractedLootTotal += lootValue

		-- Clear bag
		_bags[player.UserId] = {
			CurrentWeight = 0,
			MaxWeight = getBagCapacity(player.UserId),
			Items = {},
		}
		broadcastBagUpdate(player)

		zoneData.userId = nil
		zoneData.progress = 0

		NetworkService.FireAllClients(Constants.NETWORK.EXTRACTION_COMPLETE, {
			ZoneIndex = zoneIndex,
			ExtractingUserId = player.UserId,
			Value = lootValue,
		})

		LootService.ExtractionComplete:Fire(player, lootValue)
	end)

	zoneData.thread = thread
end

function LootService.GetBag(player: Player): BagState?
	return _bags[player.UserId]
end

function LootService.GetTeamLootTotal(): number
	return _teamLootTotal
end

function LootService.GetExtractedTotal(): number
	return _extractedLootTotal
end

function LootService.GetNodeStates(): { LootNodeState }
	local list: { LootNodeState } = {}
	for _, node in _nodes do
		list[#list + 1] = node
	end
	return list
end

return LootService
