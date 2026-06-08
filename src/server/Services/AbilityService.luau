--!strict
-- AbilityService: server-side ability validation, execution, and cooldown management.
-- Abilities are data-driven; adding a new ability requires only a data entry
-- and a handler registered below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local RobberAbilities = require(ReplicatedStorage.Shared.Abilities.RobberAbilities)
local SPECopsAbilities = require(ReplicatedStorage.Shared.Abilities.SPECopsAbilities)
local NetworkService = require(script.Parent.NetworkService)
local TeamService = require(script.Parent.TeamService)
local CombatService = require(script.Parent.CombatService)
local LootService = require(script.Parent.LootService)

type CooldownEntry = { expiresAt: number, charges: number }

-- ── AbilityService ────────────────────────────────────────────────────────────

local AbilityService = {}

-- All ability data in one flat table
local ALL_ABILITIES: { [string]: any } = {}
for id, data in RobberAbilities do
	ALL_ABILITIES[id] = data
end
for id, data in SPECopsAbilities do
	ALL_ABILITIES[id] = data
end

-- Per-player cooldowns: UserId → { abilityId → CooldownEntry }
local _cooldowns: { [number]: { [string]: CooldownEntry } } = {}

-- Active passive effects: UserId → { abilityId → true }
local _activePassives: { [number]: { [string]: boolean } } = {}

-- Active ability effects (for duration tracking): UserId → { abilityId → expiresAt }
local _activeEffects: { [number]: { [string]: number } } = {}

-- Spawned decoys / shields: cleanup on round end
local _spawnedObjects: { Instance } = {}

local _roundActive = false

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getCooldown(userId: number, abilityId: string): CooldownEntry?
	local userCds = _cooldowns[userId]
	if not userCds then return nil end
	return userCds[abilityId]
end

local function setCooldown(userId: number, abilityId: string, entry: CooldownEntry)
	if not _cooldowns[userId] then
		_cooldowns[userId] = {}
	end
	_cooldowns[userId][abilityId] = entry
	-- Sync to client
	local player = Players:GetPlayerByUserId(userId)
	if player then
		NetworkService.FireClient(Constants.NETWORK.ABILITY_COOLDOWN_SYNC, player, {
			AbilityId = abilityId,
			ExpiresAt = entry.expiresAt,
			Charges = entry.charges,
		})
	end
end

local function isOnCooldown(userId: number, abilityId: string): boolean
	local cd = getCooldown(userId, abilityId)
	if not cd then return false end
	if cd.charges > 0 then return false end
	return os.clock() < cd.expiresAt
end

local function consumeCharge(userId: number, abilityId: string, abilityData: any)
	local cd = getCooldown(userId, abilityId)
	local charges = if cd then cd.charges else abilityData.Charges
	charges -= 1
	local expiresAt: number
	if charges <= 0 then
		expiresAt = os.clock() + abilityData.Cooldown
		charges = 0
	else
		expiresAt = 0
	end
	setCooldown(userId, abilityId, { expiresAt = expiresAt, charges = charges })

	-- Schedule charge restoration if multi-charge
	if abilityData.Charges > 1 then
		task.delay(abilityData.Cooldown, function()
			if not _roundActive then return end
			local current = getCooldown(userId, abilityId)
			if current then
				local newCharges = math.min(abilityData.Charges, current.charges + 1)
				setCooldown(userId, abilityId, {
					expiresAt = if newCharges >= abilityData.Charges then 0 else current.expiresAt,
					charges = newCharges,
				})
			end
		end)
	end
end

local function getCharPosition(player: Player): Vector3?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if hrp then hrp.Position else nil
end

-- ── Ability Handlers ──────────────────────────────────────────────────────────

local Handlers: { [string]: (player: Player, data: any) -> () } = {}

Handlers["SmokeBomb"] = function(player, _data)
	local pos = getCharPosition(player)
	if not pos then return end
	-- Create smoke visual (Part as proxy; replace with particle attachment in production)
	local smoke = Instance.new("Part")
	smoke.Anchored = true
	smoke.CanCollide = false
	smoke.Transparency = 0.5
	smoke.BrickColor = BrickColor.new("Medium stone grey")
	smoke.Size = Vector3.new(
		Constants.ABILITIES.SMOKE_BOMB_RADIUS,
		Constants.ABILITIES.SMOKE_BOMB_RADIUS,
		Constants.ABILITIES.SMOKE_BOMB_RADIUS
	)
	smoke.Shape = Enum.PartType.Ball
	smoke.Position = pos
	smoke.Parent = workspace
	_spawnedObjects[#_spawnedObjects + 1] = smoke

	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "SmokeBomb",
		UserId = player.UserId,
		Position = pos,
		Duration = Constants.ABILITIES.SMOKE_BOMB_DURATION,
	})

	task.delay(Constants.ABILITIES.SMOKE_BOMB_DURATION, function()
		if smoke and smoke.Parent then
			smoke:Destroy()
		end
	end)
end

Handlers["AdrenalineRush"] = function(player, _data)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = originalSpeed * Constants.ABILITIES.ADRENALINE_SPEED_MULT

	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "AdrenalineRush",
		UserId = player.UserId,
		Duration = Constants.ABILITIES.ADRENALINE_DURATION,
	})

	task.delay(Constants.ABILITIES.ADRENALINE_DURATION, function()
		if not char or not char.Parent then return end
		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if hum then
			hum.WalkSpeed = originalSpeed
		end
	end)
end

Handlers["GrappleLauncher"] = function(player, data)
	-- The actual grapple physics runs client-side for responsiveness;
	-- server validates destination and applies position change if valid
	if not data or typeof(data.Target) ~= "Vector3" then return end

	local pos = getCharPosition(player)
	if not pos then return end

	local dist = (pos - data.Target).Magnitude
	if dist > Constants.ABILITIES.GRAPPLE_RANGE then return end

	-- Broadcast grapple start
	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "GrappleLauncher",
		UserId = player.UserId,
		Target = data.Target,
	})
end

Handlers["Hologram"] = function(player, _data)
	local pos = getCharPosition(player)
	if not pos then return end

	-- Create decoy (simple Part stand-in; production uses a cloned character)
	local decoy = Instance.new("Model")
	decoy.Name = "Hologram_" .. tostring(player.UserId)
	local body = Instance.new("Part")
	body.Size = Vector3.new(2, 5, 1)
	body.Anchored = true
	body.CFrame = CFrame.new(pos)
	body.BrickColor = player.TeamColor
	body.Parent = decoy
	decoy.Parent = workspace
	_spawnedObjects[#_spawnedObjects + 1] = decoy

	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "Hologram",
		UserId = player.UserId,
		Position = pos,
		Duration = Constants.ABILITIES.HOLOGRAM_DURATION,
	})

	task.delay(Constants.ABILITIES.HOLOGRAM_DURATION, function()
		if decoy and decoy.Parent then
			decoy:Destroy()
		end
	end)
end

Handlers["EmpDevice"] = function(player, _data)
	local pos = getCharPosition(player)
	if not pos then return end
	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "EmpDevice",
		UserId = player.UserId,
		Position = pos,
		Duration = 12,
	})
end

Handlers["Flashbang"] = function(player, data)
	if not data or typeof(data.Target) ~= "Vector3" then return end

	local pos = getCharPosition(player)
	if not pos then return end

	-- Validate throw distance (max 60 studs)
	if (pos - data.Target).Magnitude > 60 then return end

	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "Flashbang",
		UserId = player.UserId,
		Target = data.Target,
		Radius = Constants.ABILITIES.FLASHBANG_RADIUS,
		Duration = Constants.ABILITIES.FLASHBANG_DURATION,
	})
end

Handlers["SensorDart"] = function(player, data)
	if not data or typeof(data.Target) ~= "Vector3" then return end

	local pos = getCharPosition(player)
	if not pos then return end

	if (pos - data.Target).Magnitude > Constants.ABILITIES.SENSOR_DART_RANGE then return end

	-- For the duration, periodically reveal all Robbers within radius to the SPECops team
	NetworkService.FireTeam(Constants.NETWORK.ABILITY_EFFECT, "SPECops", {
		AbilityId = "SensorDart",
		UserId = player.UserId,
		Target = data.Target,
		Duration = Constants.ABILITIES.SENSOR_DART_DURATION,
	})

	task.spawn(function()
		local endTime = os.clock() + Constants.ABILITIES.SENSOR_DART_DURATION
		while os.clock() < endTime and _roundActive do
			task.wait(1)
			-- Ping Robber positions to SPECops team
			for _, robber in TeamService.GetRobbers() do
				if CombatService.IsAlive(robber) then
					local rPos = getCharPosition(robber)
					if rPos and (rPos - data.Target).Magnitude <= 50 then
						NetworkService.FireTeam(Constants.NETWORK.PING_LOCATION, "SPECops", {
							UserId = robber.UserId,
							Position = rPos,
							Source = "SensorDart",
						})
					end
				end
			end
		end
	end)
end

Handlers["PortableShield"] = function(player, data)
	if not data or typeof(data.Position) ~= "Vector3" then return end

	local pos = getCharPosition(player)
	if not pos then return end
	if (pos - data.Position).Magnitude > 10 then return end

	local shield = Instance.new("Part")
	shield.Name = "PortableShield_" .. tostring(player.UserId)
	shield.Size = Vector3.new(4, 6, 0.5)
	shield.Anchored = true
	shield.BrickColor = BrickColor.new("Bright blue")
	shield.Transparency = 0.3
	shield.CFrame = CFrame.new(data.Position)
	shield.Parent = workspace
	_spawnedObjects[#_spawnedObjects + 1] = shield

	local shieldHp = Constants.ABILITIES.SHIELD_HP

	-- Simple damage listener via proximity check is too complex without Touched events;
	-- in production use a server-side hit tracking approach
	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "PortableShield",
		UserId = player.UserId,
		Position = data.Position,
		HP = shieldHp,
	})
end

Handlers["UAVScan"] = function(player, _data)
	local pos = getCharPosition(player)
	if not pos then return end

	NetworkService.FireTeam(Constants.NETWORK.ABILITY_EFFECT, "SPECops", {
		AbilityId = "UAVScan",
		UserId = player.UserId,
		Position = pos,
		Radius = Constants.ABILITIES.UAV_SCAN_RADIUS,
		Duration = Constants.ABILITIES.UAV_SCAN_DURATION,
	})

	task.spawn(function()
		local endTime = os.clock() + Constants.ABILITIES.UAV_SCAN_DURATION
		while os.clock() < endTime and _roundActive do
			task.wait(2)
			for _, robber in TeamService.GetRobbers() do
				if CombatService.IsAlive(robber) then
					local rPos = getCharPosition(robber)
					if rPos then
						NetworkService.FireTeam(Constants.NETWORK.PING_LOCATION, "SPECops", {
							UserId = robber.UserId,
							Position = rPos,
							Source = "UAVScan",
						})
					end
				end
			end
		end
	end)
end

Handlers["StunGrenade"] = function(player, data)
	if not data or typeof(data.Target) ~= "Vector3" then return end

	local pos = getCharPosition(player)
	if not pos then return end
	if (pos - data.Target).Magnitude > 60 then return end

	NetworkService.FireAllClients(Constants.NETWORK.ABILITY_EFFECT, {
		AbilityId = "StunGrenade",
		UserId = player.UserId,
		Target = data.Target,
		Duration = 5,
	})

	-- Apply slow to any Robbers in radius
	for _, robber in TeamService.GetRobbers() do
		local rPos = getCharPosition(robber)
		if rPos and (rPos - data.Target).Magnitude <= 20 then
			local char = robber.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
				if hum then
					local orig = hum.WalkSpeed
					hum.WalkSpeed = orig * 0.4
					task.delay(5, function()
						if char and char.Parent then
							local h = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
							if h then h.WalkSpeed = orig end
						end
					end)
				end
			end
		end
	end
end

-- ── Passive application on round start ───────────────────────────────────────

local function applyPassives(player: Player, abilityIds: { string })
	for _, abilityId in abilityIds do
		local data = ALL_ABILITIES[abilityId]
		if not data or data.ActivationType ~= "Passive" then continue end

		if abilityId == "GhostWalker" then
			-- Flag in character scripts via an attribute
			local char = player.Character
			if char then char:SetAttribute("GhostWalker", true) end
			NetworkService.FireClient(Constants.NETWORK.ABILITY_EFFECT, player, {
				AbilityId = "GhostWalker", Active = true,
			})

		elseif abilityId == "MasterThief" then
			LootService.SetMasterThief(player.UserId, true)

		elseif abilityId == "Smuggler" then
			LootService.SetSmuggler(player.UserId, true)

		elseif abilityId == "IronSkin" then
			CombatService.SetHealthBonus(player, 25)

		elseif abilityId == "TacticalTraining" then
			NetworkService.FireClient(Constants.NETWORK.ABILITY_EFFECT, player, {
				AbilityId = "TacticalTraining", Active = true,
			})

		elseif abilityId == "FastReload" then
			NetworkService.FireClient(Constants.NETWORK.ABILITY_EFFECT, player, {
				AbilityId = "FastReload", Active = true,
			})

		elseif abilityId == "Ironclad" then
			CombatService.SetHealthBonus(player, 15)
		end

		if not _activePassives[player.UserId] then
			_activePassives[player.UserId] = {}
		end
		_activePassives[player.UserId][abilityId] = true
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function AbilityService.Init()
	NetworkService.OnClientEvent(Constants.NETWORK.ACTIVATE_ABILITY, function(player, abilityId, data)
		if type(abilityId) ~= "string" then return end
		AbilityService.Activate(player, abilityId, data)
	end)
end

function AbilityService.StartRound()
	_roundActive = true
	_cooldowns = {}
	_activePassives = {}
	_activeEffects = {}
	_spawnedObjects = {}

	-- Apply passive abilities from each player's loadout
	local DataService = require(script.Parent.DataService)
	for _, player in Players:GetPlayers() do
		local profile = DataService.GetProfile(player)
		if not profile then continue end

		-- Use first loadout slot; in production use the player's selected slot
		local loadout = profile.LoadoutSlots[1]
		if not loadout then continue end

		local passives: { string } = {}
		if loadout.PassiveAbility1 and loadout.PassiveAbility1 ~= "" then
			passives[#passives + 1] = loadout.PassiveAbility1
		end
		if loadout.PassiveAbility2 and loadout.PassiveAbility2 ~= "" then
			passives[#passives + 1] = loadout.PassiveAbility2
		end
		applyPassives(player, passives)
	end
end

function AbilityService.EndRound()
	_roundActive = false
	-- Destroy spawned objects
	for _, obj in _spawnedObjects do
		if obj and obj.Parent then
			obj:Destroy()
		end
	end
	_spawnedObjects = {}
end

function AbilityService.Activate(player: Player, abilityId: string, data: any)
	if not _roundActive then return end

	local abilityData = ALL_ABILITIES[abilityId]
	if not abilityData then return end
	if abilityData.ActivationType ~= "Active" then return end

	-- Team check
	if abilityData.Team ~= TeamService.GetTeamOf(player) then return end

	-- Cooldown check
	if isOnCooldown(player.UserId, abilityId) then
		NetworkService.FireClient(Constants.NETWORK.ABILITY_RESULT, player, {
			Success = false,
			AbilityId = abilityId,
			Reason = "OnCooldown",
		})
		return
	end

	-- Execute handler
	local handler = Handlers[abilityId]
	if not handler then
		warn("[AbilityService] No handler for:", abilityId)
		return
	end

	local ok, err = pcall(handler, player, data)
	if not ok then
		warn("[AbilityService] Handler error for", abilityId, ":", err)
		return
	end

	consumeCharge(player.UserId, abilityId, abilityData)

	NetworkService.FireClient(Constants.NETWORK.ABILITY_RESULT, player, {
		Success = true,
		AbilityId = abilityId,
	})
end

return AbilityService
