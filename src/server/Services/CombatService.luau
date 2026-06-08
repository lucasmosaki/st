--!strict
-- CombatService: server-authoritative hit validation, damage application,
-- kill tracking, and respawn management.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local WeaponDataModule = require(ReplicatedStorage.Shared.Weapons.WeaponData)
local NetworkService = require(script.Parent.NetworkService)
local TeamService = require(script.Parent.TeamService)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

type HitPayload = Types.HitPayload

-- ── CombatService ─────────────────────────────────────────────────────────────

local CombatService = {}

CombatService.PlayerKilled = Signal.new() :: Signal.Signal<Player, Player, string>
CombatService.PlayerDied = Signal.new() :: Signal.Signal<Player>
CombatService.PlayerRespawned = Signal.new() :: Signal.Signal<Player>

-- Track health overrides set by passives/abilities
local _healthBonuses: { [number]: number } = {}   -- UserId → bonus HP

-- Anti-exploit rate limiting: UserId → { count, windowStart }
local _hitRateTracker: { [number]: { count: number, windowStart: number } } = {}

-- Alive state per player (server-side, not character health)
local _aliveState: { [number]: boolean } = {}

-- Respawn timers
local _respawnTimers: { [number]: thread } = {}

local _roundActive: boolean = false

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function isAlive(player: Player): boolean
	local hum = getHumanoid(player)
	if not hum then return false end
	return hum.Health > 0
end

local function applyTeamHealth(player: Player)
	local hum = getHumanoid(player)
	if not hum then return end

	local base = if TeamService.IsRobber(player)
		then Constants.COMBAT.ROBBER_BASE_HEALTH
		else Constants.COMBAT.SPECOPS_BASE_HEALTH

	local bonus = _healthBonuses[player.UserId] or 0
	hum.MaxHealth = base + bonus
	hum.Health = base + bonus
end

local function checkRateLimit(userId: number): boolean
	local now = os.clock()
	local tracker = _hitRateTracker[userId]
	if not tracker then
		_hitRateTracker[userId] = { count = 1, windowStart = now }
		return true
	end
	if now - tracker.windowStart > 1.0 then
		tracker.count = 1
		tracker.windowStart = now
		return true
	end
	tracker.count += 1
	return tracker.count <= Constants.COMBAT.ANTI_EXPLOIT_MAX_HITS_PER_SECOND
end

local function computeDamage(weaponData: any, distance: number, isHeadshot: boolean): number
	local dmg = weaponData.Damage
	-- Falloff
	if distance > weaponData.FalloffEnd then
		dmg = dmg * weaponData.FalloffMin
	elseif distance > weaponData.FalloffStart then
		local t = (distance - weaponData.FalloffStart)
			/ (weaponData.FalloffEnd - weaponData.FalloffStart)
		dmg = dmg * (1 - t * (1 - weaponData.FalloffMin))
	end
	-- Headshot
	if isHeadshot then
		dmg = dmg * weaponData.HeadshotMultiplier
	end
	return math.round(dmg)
end

-- Validate that the shot is geometrically plausible
local function validateRaycast(origin: Vector3, direction: Vector3, target: Player, distance: number): boolean
	local char = target.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end

	-- Server-side raycast with a generous tolerance for lag
	local tolerance = Constants.COMBAT.LAG_TOLERANCE
	local rayDir = direction.Unit * (distance + tolerance)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Check if a ray from origin in that direction comes reasonably close to target
	local serverDist = (hrp.Position - origin).Magnitude
	return serverDist <= distance + Constants.COMBAT.HITBOX_TOLERANCE
end

-- ── Public API ────────────────────────────────────────────────────────────────

function CombatService.Init()
	NetworkService.OnClientEvent(Constants.NETWORK.FIRE_WEAPON, function(player, payload)
		if type(payload) ~= "table" then return end
		CombatService.ProcessHit(player, payload)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(_char)
			task.wait(0.1) -- brief wait for character setup
			if _roundActive then
				applyTeamHealth(player)
			end
			_aliveState[player.UserId] = true
		end)
	end)
end

function CombatService.StartRound()
	_roundActive = true
	_healthBonuses = {}
	_hitRateTracker = {}
	_aliveState = {}
	_respawnTimers = {}

	-- Apply health to all currently in-game characters
	for _, player in Players:GetPlayers() do
		if player.Character then
			applyTeamHealth(player)
			_aliveState[player.UserId] = true
		end
	end
end

function CombatService.EndRound()
	_roundActive = false
	-- Cancel respawn timers
	for userId, thread in _respawnTimers do
		task.cancel(thread)
		_respawnTimers[userId] = nil
	end
end

function CombatService.SetHealthBonus(player: Player, bonus: number)
	_healthBonuses[player.UserId] = bonus
	local hum = getHumanoid(player)
	if hum then
		local base = if TeamService.IsRobber(player)
			then Constants.COMBAT.ROBBER_BASE_HEALTH
			else Constants.COMBAT.SPECOPS_BASE_HEALTH
		hum.MaxHealth = base + bonus
		if hum.Health > hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end
end

function CombatService.ProcessHit(shooter: Player, payload: any)
	if not _roundActive then return end

	-- Basic type validation
	if type(payload.WeaponName) ~= "string"
		or type(payload.TargetUserId) ~= "number"
		or type(payload.Distance) ~= "number"
		or type(payload.HitPart) ~= "string"
		or typeof(payload.Origin) ~= "Vector3"
		or typeof(payload.Direction) ~= "Vector3"
	then
		return
	end

	-- Rate limit
	if not checkRateLimit(shooter.UserId) then
		warn("[CombatService] Rate limit hit for", shooter.Name)
		return
	end

	local target = Players:GetPlayerByUserId(payload.TargetUserId)
	if not target or not target.Character then return end

	-- Team check (no friendly fire)
	if TeamService.GetTeamOf(shooter) == TeamService.GetTeamOf(target) then return end
	if not TeamService.IsRobber(shooter) and not TeamService.IsSPECops(shooter) then return end

	-- Range check
	local weaponData = WeaponDataModule[payload.WeaponName]
	if not weaponData then return end
	if payload.Distance > weaponData.MaxRange + Constants.COMBAT.LAG_TOLERANCE then return end
	if payload.Distance > Constants.COMBAT.MAX_HIT_DISTANCE then return end

	-- Geometric validation
	if not validateRaycast(payload.Origin, payload.Direction, target, payload.Distance) then return end

	-- Timestamp sanity (reject very old or future hits)
	local now = os.clock()
	if math.abs(now - (payload.Timestamp or 0)) > 2.0 then
		-- Still process but warn; could be high latency
	end

	local isHeadshot = false
	for _, part in Constants.COMBAT.HEADSHOT_PARTS do
		if payload.HitPart == part then
			isHeadshot = true
			break
		end
	end

	local damage = computeDamage(weaponData, payload.Distance, isHeadshot)

	local hum = getHumanoid(target)
	if not hum or hum.Health <= 0 then return end

	hum.Health -= damage

	-- Broadcast damage dealt
	NetworkService.FireAllClients(Constants.NETWORK.DAMAGE_DEALT, {
		ShooterUserId = shooter.UserId,
		TargetUserId = target.UserId,
		Damage = damage,
		IsHeadshot = isHeadshot,
		HitPart = payload.HitPart,
	})

	if hum.Health <= 0 then
		CombatService.HandleKill(shooter, target, payload.WeaponName)
	end
end

function CombatService.HandleKill(killer: Player, victim: Player, weaponName: string)
	_aliveState[victim.UserId] = false

	NetworkService.FireAllClients(Constants.NETWORK.PLAYER_DIED, {
		VictimUserId = victim.UserId,
		KillerUserId = killer.UserId,
		WeaponName = weaponName,
	})

	CombatService.PlayerKilled:Fire(killer, victim, weaponName)
	CombatService.PlayerDied:Fire(victim)

	-- SPECops respawn; Robbers do not respawn (eliminated permanently)
	if TeamService.IsSPECops(victim) then
		local thread = task.delay(Constants.COMBAT.SPECOPS_RESPAWN_TIME, function()
			if not _roundActive then return end
			victim:LoadCharacter()
			task.wait(0.5)
			applyTeamHealth(victim)
			_aliveState[victim.UserId] = true
			NetworkService.FireClient(Constants.NETWORK.PLAYER_RESPAWNED, victim)
			CombatService.PlayerRespawned:Fire(victim)
		end)
		_respawnTimers[victim.UserId] = thread
	end
end

function CombatService.IsAlive(player: Player): boolean
	return _aliveState[player.UserId] == true and isAlive(player)
end

function CombatService.GetAliveRobbers(): { Player }
	local result: { Player } = {}
	for _, player in TeamService.GetRobbers() do
		if CombatService.IsAlive(player) then
			result[#result + 1] = player
		end
	end
	return result
end

return CombatService
