--!strict
-- CombatController: client-side FPS input, raycast, recoil, and weapon UI.
-- Sends hit data to the server for authoritative validation.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local WeaponDataModule = require(ReplicatedStorage.Shared.Weapons.WeaponData)

-- Remote access via folder created by NetworkService
local function getRemote(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- ── CombatController ──────────────────────────────────────────────────────────

local CombatController = {}

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Weapon state
local _equipped: string? = nil    -- current weapon name
local _magazine: number = 0
local _isReloading: boolean = false
local _lastFired: number = 0
local _canFire: boolean = true

-- Recoil accumulator
local _recoilOffset = Vector2.new(0, 0)
local _recoilRecoveryRate = 3.0   -- studs/s recovery

-- Passive bonuses applied by AbilityController
local _recoilMultiplier: number = 1.0
local _reloadMultiplier: number = 1.0

-- Connections
local _connections: { RBXScriptConnection } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getWeaponData()
	if not _equipped then return nil end
	return WeaponDataModule[_equipped]
end

local function getCharacter()
	return LocalPlayer.Character
end

local function getHRP(): BasePart?
	local char = getCharacter()
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Build a RaycastParams that ignores the local character
local function buildRayParams(): RaycastParams
	local params = RaycastParams.new()
	local char = getCharacter()
	if char then
		params.FilterDescendantsInstances = { char }
	end
	params.FilterType = Enum.RaycastFilterType.Exclude
	return params
end

local function screenToWorldRay(): (Vector3, Vector3)
	local viewportSize = Camera.ViewportSize
	local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)

	-- Apply recoil offset to center
	local offsetCenter = center + Vector2.new(_recoilOffset.X * 50, -_recoilOffset.Y * 50)

	local unitRay = Camera:ScreenPointToRay(offsetCenter.X, offsetCenter.Y)
	return unitRay.Origin, unitRay.Direction
end

local function applySpread(direction: Vector3, spreadDeg: number): Vector3
	if spreadDeg <= 0 then return direction end
	local spreadRad = math.rad(spreadDeg)
	local rx = (math.random() - 0.5) * 2 * spreadRad
	local ry = (math.random() - 0.5) * 2 * spreadRad
	local cf = CFrame.new(Vector3.zero, direction)
	return (cf * CFrame.Angles(rx, ry, 0)).LookVector
end

local function applyRecoil(weaponData: any)
	_recoilOffset = Vector2.new(
		_recoilOffset.X + (math.random() - 0.5) * weaponData.RecoilX * _recoilMultiplier,
		_recoilOffset.Y + weaponData.RecoilY * _recoilMultiplier
	)
	-- Clamp recoil
	_recoilOffset = Vector2.new(
		math.clamp(_recoilOffset.X, -0.05, 0.05),
		math.clamp(_recoilOffset.Y, 0, 0.08)
	)
end

-- ── Firing ────────────────────────────────────────────────────────────────────

local function fireSinglePellet(weaponData: any)
	local origin, dir = screenToWorldRay()
	local spreadDir = applySpread(dir, weaponData.Spread)
	local params = buildRayParams()

	local result = workspace:Raycast(origin, spreadDir * weaponData.MaxRange, params)
	if not result then return end

	local hitInstance = result.Instance
	local hitModel = hitInstance:FindFirstAncestorOfClass("Model")
	local hitPlayer = if hitModel then Players:GetPlayerFromCharacter(hitModel) else nil

	if hitPlayer and hitPlayer ~= LocalPlayer then
		local distance = (result.Position - origin).Magnitude
		local partName = hitInstance.Name

		getRemote(Constants.NETWORK.FIRE_WEAPON):FireServer({
			WeaponName = _equipped,
			TargetUserId = hitPlayer.UserId,
			HitPart = partName,
			Distance = distance,
			Origin = origin,
			Direction = spreadDir,
			Timestamp = os.clock(),
		})
	end
end

local function fireWeapon()
	local weaponData = getWeaponData()
	if not weaponData then return end
	if _magazine <= 0 then
		CombatController.StartReload()
		return
	end
	if _isReloading then return end

	local now = os.clock()
	if now - _lastFired < (1 / weaponData.FireRate) then return end
	_lastFired = now
	_magazine -= 1

	local pellets = weaponData.PelletsPerShot or 1
	for _ = 1, pellets do
		fireSinglePellet(weaponData)
	end

	applyRecoil(weaponData)
	-- Local feedback: muzzle flash / sound handled by Tool scripts in production
end

-- ── Reload ────────────────────────────────────────────────────────────────────

function CombatController.StartReload()
	local weaponData = getWeaponData()
	if not weaponData then return end
	if _isReloading then return end
	if _magazine >= weaponData.MagazineSize then return end

	_isReloading = true
	local reloadTime = weaponData.ReloadTime * _reloadMultiplier
	task.delay(reloadTime, function()
		_magazine = weaponData.MagazineSize
		_isReloading = false
		-- Update ammo HUD
		CombatController.AmmoChanged:Fire(_magazine, weaponData.MagazineSize)
	end)
end

-- ── Signals ───────────────────────────────────────────────────────────────────

local Signal = require(ReplicatedStorage.Shared.Utility.Signal)
CombatController.AmmoChanged = Signal.new() :: Signal.Signal<number, number>
CombatController.HitConfirmed = Signal.new() :: Signal.Signal<{any}>
CombatController.PlayerDied = Signal.new() :: Signal.Signal<{any}>

-- ── Equip / Unequip ───────────────────────────────────────────────────────────

function CombatController.Equip(weaponName: string)
	local weaponData = WeaponDataModule[weaponName]
	if not weaponData then
		warn("[CombatController] Unknown weapon:", weaponName)
		return
	end
	_equipped = weaponName
	_magazine = weaponData.MagazineSize
	_isReloading = false
	_lastFired = 0
	_recoilOffset = Vector2.zero
	CombatController.AmmoChanged:Fire(_magazine, weaponData.MagazineSize)
end

function CombatController.Unequip()
	_equipped = nil
	_isReloading = false
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function CombatController.Init()
	-- Mouse button 1 fires
	local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not _equipped then return end
			local weaponData = getWeaponData()
			if weaponData and weaponData.FireMode == "Automatic" then
				_canFire = true
			else
				fireWeapon()
			end
		end
	end)
	_connections[#_connections + 1] = inputConn

	local inputEndConn = UserInputService.InputEnded:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			_canFire = false
		end
	end)
	_connections[#_connections + 1] = inputEndConn

	local reloadConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.R then
			CombatController.StartReload()
		end
	end)
	_connections[#_connections + 1] = reloadConn

	-- Automatic fire loop
	local autoConn = RunService.Heartbeat:Connect(function(_dt)
		if not _canFire then return end
		if not _equipped then return end
		local weaponData = getWeaponData()
		if not weaponData or weaponData.FireMode ~= "Automatic" then return end
		fireWeapon()
	end)
	_connections[#_connections + 1] = autoConn

	-- Recoil recovery
	local recovConn = RunService.Heartbeat:Connect(function(dt)
		if _recoilOffset.Magnitude > 0.001 then
			_recoilOffset = _recoilOffset:Lerp(Vector2.zero, dt * _recoilRecoveryRate)
		end
	end)
	_connections[#_connections + 1] = recovConn

	-- Server hit confirmations
	getRemote(Constants.NETWORK.HIT_RESULT).OnClientEvent:Connect(function(data)
		CombatController.HitConfirmed:Fire(data)
	end)

	getRemote(Constants.NETWORK.PLAYER_DIED).OnClientEvent:Connect(function(data)
		CombatController.PlayerDied:Fire(data)
	end)
end

function CombatController.SetRecoilMultiplier(mult: number)
	_recoilMultiplier = mult
end

function CombatController.SetReloadMultiplier(mult: number)
	_reloadMultiplier = mult
end

function CombatController.GetAmmo(): (number, number)
	local weaponData = getWeaponData()
	return _magazine, if weaponData then weaponData.MagazineSize else 0
end

function CombatController.Destroy()
	for _, conn in _connections do
		conn:Disconnect()
	end
	_connections = {}
end

return CombatController
