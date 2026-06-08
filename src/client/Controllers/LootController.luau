--!strict
-- LootController: proximity detection, interact prompt, progress bar, and bag HUD.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

type LootNodeState = Types.LootNodeState
type BagState = Types.BagState

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- ── LootController ────────────────────────────────────────────────────────────

local LootController = {}

LootController.BagUpdated = Signal.new() :: Signal.Signal<BagState>
LootController.NodeUpdated = Signal.new() :: Signal.Signal<LootNodeState>
LootController.InteractionProgress = Signal.new() :: Signal.Signal<string, number>
LootController.ExtractionProgress = Signal.new() :: Signal.Signal<{any}>
LootController.NearbyNodeChanged = Signal.new() :: Signal.Signal<LootNodeState?>

local LocalPlayer = Players.LocalPlayer

-- Client-side node states replicated from server
local _nodeStates: { [string]: LootNodeState } = {}
-- Extraction zone positions (set when round starts)
local _extractionZones: { { Position: Vector3, Radius: number } } = {}

-- Current bag
local _bag: BagState? = nil

-- Nearest node the player can interact with
local _nearestNode: LootNodeState? = nil
local _nearestZoneIndex: number? = nil

-- Interaction state
local _isInteracting: boolean = false
local _interactingNodeId: string? = nil

local _isExtracting: boolean = false

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getHRP(): BasePart?
	local char = LocalPlayer.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nodeHasItems(node: LootNodeState): boolean
	for _, item in node.Items do
		if item.Active then return true end
	end
	return false
end

-- ── Per-frame proximity checks ────────────────────────────────────────────────

local function tickProximity()
	local hrp = getHRP()
	if not hrp then
		if _nearestNode then
			_nearestNode = nil
			LootController.NearbyNodeChanged:Fire(nil)
		end
		_nearestZoneIndex = nil
		return
	end
	local pos = hrp.Position

	-- Find nearest loot node
	local best: LootNodeState? = nil
	local bestDist = Constants.LOOT.LOOT_INTERACT_DISTANCE + 0.1

	for _, node in _nodeStates do
		if not nodeHasItems(node) then continue end
		local d = (pos - node.Position).Magnitude
		if d < bestDist then
			bestDist = d
			best = node
		end
	end

	if best ~= _nearestNode then
		_nearestNode = best
		LootController.NearbyNodeChanged:Fire(best)
	end

	-- Find nearest extraction zone
	local nearestZone: number? = nil
	for i, zone in _extractionZones do
		if (pos - zone.Position).Magnitude <= zone.Radius then
			nearestZone = i
			break
		end
	end
	_nearestZoneIndex = nearestZone
end

-- ── Input handling ────────────────────────────────────────────────────────────

local function handleInteractInput()
	if _nearestNode and not _isInteracting then
		_isInteracting = true
		_interactingNodeId = _nearestNode.Id
		getRemote(Constants.NETWORK.INTERACT_LOOT):FireServer(_nearestNode.Id)
	elseif _nearestZoneIndex and not _isExtracting then
		_isExtracting = true
		getRemote(Constants.NETWORK.REQUEST_EXTRACTION):FireServer(_nearestZoneIndex)
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LootController.Init()
	-- Proximity loop
	RunService.Heartbeat:Connect(function(_dt)
		tickProximity()
	end)

	-- E key to interact
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.E then
			handleInteractInput()
		end
	end)

	-- Node state updates from server
	getRemote(Constants.NETWORK.LOOT_NODE_STATE).OnClientEvent:Connect(function(nodeState: LootNodeState)
		if not nodeState or not nodeState.Id then return end
		_nodeStates[nodeState.Id] = nodeState
		LootController.NodeUpdated:Fire(nodeState)
	end)

	-- Bag updates
	getRemote(Constants.NETWORK.BAG_UPDATE).OnClientEvent:Connect(function(bagState: BagState)
		_bag = bagState
		LootController.BagUpdated:Fire(bagState)
	end)

	-- Interaction progress
	getRemote(Constants.NETWORK.LOOT_INTERACTION_PROGRESS).OnClientEvent:Connect(
		function(nodeId: string, progress: number)
			if progress <= 0 then
				_isInteracting = false
				_interactingNodeId = nil
			end
			LootController.InteractionProgress:Fire(nodeId, progress)
		end
	)

	-- Extraction zones activated
	getRemote(Constants.NETWORK.EXTRACTION_ZONE_ACTIVATED).OnClientEvent:Connect(
		function(zones: { { Position: Vector3, Radius: number } })
			_extractionZones = zones
		end
	)

	-- Extraction progress
	getRemote(Constants.NETWORK.EXTRACTION_PROGRESS).OnClientEvent:Connect(function(data)
		LootController.ExtractionProgress:Fire(data)
	end)

	-- Extraction complete
	getRemote(Constants.NETWORK.EXTRACTION_COMPLETE).OnClientEvent:Connect(function(_data)
		_isExtracting = false
	end)

	-- Extraction interrupted
	getRemote(Constants.NETWORK.EXTRACTION_INTERRUPTED).OnClientEvent:Connect(function(_zoneIndex)
		_isExtracting = false
	end)
end

function LootController.GetBag(): BagState?
	return _bag
end

function LootController.GetNearestNode(): LootNodeState?
	return _nearestNode
end

function LootController.IsNearExtractionZone(): boolean
	return _nearestZoneIndex ~= nil
end

function LootController.IsInteracting(): boolean
	return _isInteracting
end

return LootController
