--!strict
-- AbilityController: client-side ability activation, cooldown display, and
-- passive effect application (recoil/reload multipliers).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local RobberAbilities = require(ReplicatedStorage.Shared.Abilities.RobberAbilities)
local SPECopsAbilities = require(ReplicatedStorage.Shared.Abilities.SPECopsAbilities)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)
local CombatController = require(script.Parent.CombatController)

local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- ── AbilityController ─────────────────────────────────────────────────────────

local AbilityController = {}

AbilityController.CooldownUpdated = Signal.new() :: Signal.Signal<string, number, number>
AbilityController.EffectReceived = Signal.new() :: Signal.Signal<{any}>

local LocalPlayer = Players.LocalPlayer

-- Cooldown tracking (clientside mirror)
local _cooldowns: { [string]: { expiresAt: number, charges: number } } = {}

-- Active ability slot (key binding)
local _equippedAbility: string? = nil

-- All ability data merged
local ALL_ABILITIES: { [string]: any } = {}
for id, data in RobberAbilities do
	ALL_ABILITIES[id] = data
end
for id, data in SPECopsAbilities do
	ALL_ABILITIES[id] = data
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function isOnCooldown(abilityId: string): boolean
	local cd = _cooldowns[abilityId]
	if not cd then return false end
	if cd.charges > 0 then return false end
	return os.clock() < cd.expiresAt
end

local function getCharPosition(): Vector3?
	local char = LocalPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if hrp then hrp.Position else nil
end

local function getMouseWorldTarget(): Vector3?
	local camera = workspace.CurrentCamera
	local vp = camera.ViewportSize
	local unitRay = camera:ScreenPointToRay(vp.X / 2, vp.Y / 2)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 300)
	return if result then result.Position else unitRay.Origin + unitRay.Direction * 50
end

-- ── Activation ────────────────────────────────────────────────────────────────

function AbilityController.Activate(abilityId: string, extraData: any?)
	local data = ALL_ABILITIES[abilityId]
	if not data then return end
	if isOnCooldown(abilityId) then
		-- Provide cooldown feedback (flash icon)
		AbilityController.CooldownUpdated:Fire(
			abilityId,
			_cooldowns[abilityId].expiresAt - os.clock(),
			0
		)
		return
	end

	local payload: any = extraData

	-- For throwable abilities, attach target position
	if abilityId == "Flashbang" or abilityId == "StunGrenade" then
		payload = { Target = getMouseWorldTarget() or Vector3.zero }
	elseif abilityId == "GrappleLauncher" then
		payload = { Target = getMouseWorldTarget() or Vector3.zero }
	elseif abilityId == "SensorDart" then
		payload = { Target = getMouseWorldTarget() or Vector3.zero }
	elseif abilityId == "PortableShield" then
		local pos = getCharPosition()
		local camera = workspace.CurrentCamera
		payload = { Position = pos and (pos + camera.CFrame.LookVector * 3) or Vector3.zero }
	end

	getRemote(Constants.NETWORK.ACTIVATE_ABILITY):FireServer(abilityId, payload)

	-- Optimistic client-side cooldown (server will sync authoritative)
	if data.Cooldown > 0 then
		local curCharges = (_cooldowns[abilityId] and _cooldowns[abilityId].charges) or data.Charges
		curCharges -= 1
		if curCharges < 0 then curCharges = 0 end
		_cooldowns[abilityId] = {
			expiresAt = if curCharges <= 0 then os.clock() + data.Cooldown else 0,
			charges = curCharges,
		}
		AbilityController.CooldownUpdated:Fire(abilityId, data.Cooldown, curCharges)
	end
end

-- ── Passive Effect Handlers ───────────────────────────────────────────────────

local function handlePassiveEffect(effectData: any)
	if not effectData then return end
	local id = effectData.AbilityId
	if id == "TacticalTraining" and effectData.Active then
		CombatController.SetRecoilMultiplier(Constants.ABILITIES.TACTICAL_RECOIL_MULT)
	elseif id == "FastReload" and effectData.Active then
		CombatController.SetReloadMultiplier(Constants.ABILITIES.FAST_RELOAD_MULT)
	elseif id == "GhostWalker" and effectData.Active then
		-- Footstep sounds reduced on client-side (handled in sound controller)
		LocalPlayer.Character and
			LocalPlayer.Character:SetAttribute("GhostWalker", true)
	end
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function AbilityController.Init()
	-- Q = active ability
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Q then
			if _equippedAbility then
				AbilityController.Activate(_equippedAbility)
			end
		end
	end)

	-- Server sync of authoritative cooldowns
	getRemote(Constants.NETWORK.ABILITY_COOLDOWN_SYNC).OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		_cooldowns[data.AbilityId] = {
			expiresAt = data.ExpiresAt,
			charges = data.Charges,
		}
		AbilityController.CooldownUpdated:Fire(
			data.AbilityId,
			math.max(0, data.ExpiresAt - os.clock()),
			data.Charges
		)
	end)

	-- Ability effects (visual/passive)
	getRemote(Constants.NETWORK.ABILITY_EFFECT).OnClientEvent:Connect(function(effectData)
		AbilityController.EffectReceived:Fire(effectData)
		handlePassiveEffect(effectData)
	end)

	-- Result feedback
	getRemote(Constants.NETWORK.ABILITY_RESULT).OnClientEvent:Connect(function(result)
		if not result.Success and result.Reason == "OnCooldown" then
			-- Could flash UI here
		end
	end)
end

function AbilityController.SetEquippedAbility(abilityId: string?)
	_equippedAbility = abilityId
end

function AbilityController.GetCooldownRemaining(abilityId: string): number
	local cd = _cooldowns[abilityId]
	if not cd then return 0 end
	return math.max(0, cd.expiresAt - os.clock())
end

function AbilityController.GetCharges(abilityId: string): number
	local cd = _cooldowns[abilityId]
	local data = ALL_ABILITIES[abilityId]
	if not cd then return if data then data.Charges else 0 end
	return cd.charges
end

return AbilityController
