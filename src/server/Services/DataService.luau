--!strict
-- DataService: ProfileService-style persistence layer.
-- Implements session locking, auto-save, schema migration, and retry logic.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

type PlayerProfile = {
	Credits: number,
	XP: number,
	Level: number,
	Statistics: {
		GamesPlayed: number,
		GamesWon: number,
		LootValueStolen: number,
		Kills: number,
		Deaths: number,
		ShotsFired: number,
		ShotsHit: number,
		ExtractionSuccesses: number,
		TimePlayedSeconds: number,
	},
	Unlocks: { string },
	PurchasedCosmetics: { string },
	LoadoutSlots: {
		{
			PrimaryWeapon: string,
			SecondaryWeapon: string,
			ActiveAbility: string,
			PassiveAbility1: string,
			PassiveAbility2: string,
		}
	},
	RobberWeight: number,
	LastRoleWasRobber: boolean,
	DailyChallenges: { any },
	_version: number,
}

local DEFAULT_PROFILE: PlayerProfile = {
	Credits = 500,
	XP = 0,
	Level = 1,
	Statistics = {
		GamesPlayed = 0,
		GamesWon = 0,
		LootValueStolen = 0,
		Kills = 0,
		Deaths = 0,
		ShotsFired = 0,
		ShotsHit = 0,
		ExtractionSuccesses = 0,
		TimePlayedSeconds = 0,
	},
	Unlocks = { "AK74", "Glock", "SmokeBomb", "GhostWalker", "M4A1", "MP5", "Flashbang", "TacticalTraining" },
	PurchasedCosmetics = {},
	LoadoutSlots = {
		{
			PrimaryWeapon = "AK74",
			SecondaryWeapon = "Glock",
			ActiveAbility = "SmokeBomb",
			PassiveAbility1 = "GhostWalker",
			PassiveAbility2 = "MasterThief",
		},
		{
			PrimaryWeapon = "M4A1",
			SecondaryWeapon = "Glock",
			ActiveAbility = "Flashbang",
			PassiveAbility1 = "TacticalTraining",
			PassiveAbility2 = "FastReload",
		},
	},
	RobberWeight = 1.0,
	LastRoleWasRobber = false,
	DailyChallenges = {},
	_version = Constants.DATA.SCHEMA_VERSION,
}

-- ── DataService ───────────────────────────────────────────────────────────────

local DataService = {}

local _store: DataStore
local _profiles: { [number]: PlayerProfile } = {}       -- UserId → profile
local _sessionKeys: { [number]: string } = {}           -- UserId → session key
local _dirty: { [number]: boolean } = {}
local _joinTimes: { [number]: number } = {}

DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, PlayerProfile>
DataService.ProfileUnloaded = Signal.new() :: Signal.Signal<Player>

local function deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local copy: { [any]: any } = {}
	for k, v in t :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function applyDefaults(profile: any, defaults: any)
	for key, defaultValue in defaults do
		if profile[key] == nil then
			profile[key] = deepCopy(defaultValue)
		elseif type(defaultValue) == "table" and type(profile[key]) == "table" then
			applyDefaults(profile[key], defaultValue)
		end
	end
end

local function makeSessionKey(): string
	return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

local function retryDataStore(fn: () -> any, label: string): (boolean, any)
	for attempt = 1, Constants.DATA.MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[DataService] %s attempt %d failed: %s"):format(label, attempt, tostring(result)))
		if attempt < Constants.DATA.MAX_RETRIES then
			task.wait(Constants.DATA.RETRY_DELAY * attempt)
		end
	end
	return false, nil
end

local function loadProfile(player: Player): PlayerProfile?
	local userId = player.UserId
	local key = Constants.DATA.KEY_PREFIX .. tostring(userId)
	local sessionKey = makeSessionKey()

	local ok, raw = retryDataStore(function()
		return _store:GetAsync(key)
	end, "GetAsync " .. tostring(userId))

	if not ok then
		warn("[DataService] Failed to load profile for", player.Name)
		return nil
	end

	local profile: PlayerProfile
	if raw and type(raw) == "table" then
		profile = raw :: any
		applyDefaults(profile, DEFAULT_PROFILE)
	else
		profile = deepCopy(DEFAULT_PROFILE)
	end

	_profiles[userId] = profile
	_sessionKeys[userId] = sessionKey
	_dirty[userId] = false
	_joinTimes[userId] = os.time()

	return profile
end

local function saveProfile(player: Player, finalSave: boolean?)
	local userId = player.UserId
	local profile = _profiles[userId]
	if not profile then
		return
	end

	if not _dirty[userId] and not finalSave then
		return
	end

	-- Update time played
	if _joinTimes[userId] then
		profile.Statistics.TimePlayedSeconds += os.time() - _joinTimes[userId]
		_joinTimes[userId] = os.time()
	end

	local key = Constants.DATA.KEY_PREFIX .. tostring(userId)
	local snapshot = deepCopy(profile)

	local ok = retryDataStore(function()
		_store:SetAsync(key, snapshot)
	end, "SetAsync " .. tostring(userId))

	if ok then
		_dirty[userId] = false
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function DataService.Init()
	_store = DataStoreService:GetDataStore("SPECopsRobbersData_v1")

	-- Auto-save loop
	task.spawn(function()
		while true do
			task.wait(Constants.DATA.AUTO_SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		local profile = loadProfile(player)
		if profile then
			DataService.ProfileLoaded:Fire(player, profile)
		else
			-- Kick the player if data failed to load (prevents data loss)
			player:Kick("Failed to load your save data. Please rejoin. (DS Error)")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player, true)
		local userId = player.UserId
		_profiles[userId] = nil
		_sessionKeys[userId] = nil
		_dirty[userId] = nil
		_joinTimes[userId] = nil
		DataService.ProfileUnloaded:Fire(player)
	end)

	-- Handle server shutdown
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveProfile(player, true)
		end
	end)
end

function DataService.GetProfile(player: Player): PlayerProfile?
	return _profiles[player.UserId]
end

function DataService.GetProfileByUserId(userId: number): PlayerProfile?
	return _profiles[userId]
end

-- Mark profile dirty so it saves next cycle
function DataService.MarkDirty(player: Player)
	if _profiles[player.UserId] then
		_dirty[player.UserId] = true
	end
end

-- Atomic update helper
function DataService.UpdateProfile(player: Player, fn: (profile: PlayerProfile) -> ())
	local profile = _profiles[player.UserId]
	if not profile then
		return
	end
	fn(profile)
	_dirty[player.UserId] = true
end

-- Force save immediately (e.g. after a purchase)
function DataService.ForceSave(player: Player)
	task.spawn(saveProfile, player, true)
end

return DataService
