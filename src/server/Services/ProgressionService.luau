--!strict
-- ProgressionService: XP, levelling, credit awards, and statistics tracking.
-- Fires RewardsSummary to clients at the end of each round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local NetworkService = require(script.Parent.NetworkService)

type PlayerProfile = Types.PlayerProfile
type RoundSummary = Types.RoundSummary

-- ── ProgressionService ────────────────────────────────────────────────────────

local ProgressionService = {}

-- Round-local stat accumulators: UserId → deltas
local _roundKills: { [number]: number } = {}
local _roundLootValue: { [number]: number } = {}
local _roundExtractions: { [number]: number } = {}
local _roundShotsFired: { [number]: number } = {}
local _roundShotsHit: { [number]: number } = {}
local _roundStartTime: number = 0

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- XP required to reach the next level from the current one
local function xpForLevel(level: number): number
	return math.floor(
		Constants.PROGRESSION.BASE_XP_PER_LEVEL
			* (Constants.PROGRESSION.XP_SCALING ^ (level - 1))
	)
end

local function applyXP(profile: PlayerProfile, amount: number): number
	profile.XP += amount
	local gained = 0
	while profile.Level < Constants.PROGRESSION.MAX_LEVEL
		and profile.XP >= xpForLevel(profile.Level)
	do
		profile.XP -= xpForLevel(profile.Level)
		profile.Level += 1
		gained += 1
	end
	return gained
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ProgressionService.Init()
	-- nothing async needed here
end

function ProgressionService.StartRound()
	_roundKills = {}
	_roundLootValue = {}
	_roundExtractions = {}
	_roundShotsFired = {}
	_roundShotsHit = {}
	_roundStartTime = os.time()
end

function ProgressionService.RecordKill(killer: Player)
	local uid = killer.UserId
	_roundKills[uid] = (_roundKills[uid] or 0) + 1
end

function ProgressionService.RecordLoot(player: Player, value: number)
	local uid = player.UserId
	_roundLootValue[uid] = (_roundLootValue[uid] or 0) + value
end

function ProgressionService.RecordExtraction(player: Player, value: number)
	local uid = player.UserId
	_roundExtractions[uid] = (_roundExtractions[uid] or 0) + 1
	_roundLootValue[uid] = (_roundLootValue[uid] or 0) + value -- extraction = loot crystalised
end

function ProgressionService.RecordShotFired(player: Player)
	local uid = player.UserId
	_roundShotsFired[uid] = (_roundShotsFired[uid] or 0) + 1
end

function ProgressionService.RecordShotHit(player: Player)
	local uid = player.UserId
	_roundShotsHit[uid] = (_roundShotsHit[uid] or 0) + 1
end

-- Called by RoundService after win condition is determined
function ProgressionService.FinaliseRound(summary: RoundSummary)
	local duration = os.time() - _roundStartTime

	for _, player in Players:GetPlayers() do
		local uid = player.UserId
		DataService.UpdateProfile(player, function(profile)
			-- Statistics
			profile.Statistics.GamesPlayed += 1
			profile.Statistics.Kills += (_roundKills[uid] or 0)
			profile.Statistics.LootValueStolen += (_roundLootValue[uid] or 0)
			profile.Statistics.ExtractionSuccesses += (_roundExtractions[uid] or 0)
			profile.Statistics.ShotsFired += (_roundShotsFired[uid] or 0)
			profile.Statistics.ShotsHit += (_roundShotsHit[uid] or 0)
			profile.Statistics.TimePlayedSeconds += duration

			-- Compute rewards
			local creditsEarned = 0
			local xpEarned = 0

			creditsEarned += (_roundKills[uid] or 0) * Constants.PROGRESSION.CREDITS_PER_KILL
			xpEarned += (_roundKills[uid] or 0) * Constants.PROGRESSION.XP_PER_KILL

			creditsEarned += math.floor(
				(_roundLootValue[uid] or 0) * Constants.PROGRESSION.CREDITS_PER_LOOT_VALUE
			)
			xpEarned += math.floor(
				(_roundLootValue[uid] or 0) * Constants.PROGRESSION.XP_PER_LOOT_VALUE
			)

			creditsEarned += (_roundExtractions[uid] or 0) * Constants.PROGRESSION.CREDITS_PER_EXTRACTION
			xpEarned += (_roundExtractions[uid] or 0) * Constants.PROGRESSION.XP_PER_EXTRACTION

			-- Win bonus
			local teamName = if player.Team then player.Team.Name else ""
			if teamName == summary.WinningTeam then
				profile.Statistics.GamesWon += 1
				creditsEarned += Constants.PROGRESSION.CREDITS_PER_WIN
				xpEarned += Constants.PROGRESSION.XP_PER_WIN
			end

			-- XP boosters from cosmetics would multiply here
			profile.Credits += creditsEarned
			local levelsGained = applyXP(profile, xpEarned)

			-- Notify client
			NetworkService.FireClient(Constants.NETWORK.REWARDS_SUMMARY, player, {
				CreditsEarned = creditsEarned,
				XPEarned = xpEarned,
				LevelsGained = levelsGained,
				NewLevel = profile.Level,
				WinningTeam = summary.WinningTeam,
				WinReason = summary.WinReason,
			})

			-- Full profile sync
			NetworkService.FireClient(Constants.NETWORK.PROFILE_SYNC, player, {
				Credits = profile.Credits,
				XP = profile.XP,
				Level = profile.Level,
				Statistics = profile.Statistics,
			})
		end)

		DataService.ForceSave(player)
	end
end

function ProgressionService.GetXPForLevel(level: number): number
	return xpForLevel(level)
end

return ProgressionService
