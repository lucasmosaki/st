--!strict
-- Server bootstrap: initialises all services in dependency order, then starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Services must be referenced through the Script object (this Script is the Server folder)
local Services = script.Services

-- Phase 1 — services with no service dependencies
local NetworkService = require(Services.NetworkService)
local DataService = require(Services.DataService)

-- Phase 2 — services that depend only on Network/Data
local TeamService = require(Services.TeamService)
local ProgressionService = require(Services.ProgressionService)

-- Phase 3 — services that depend on Team/Data
local MapService = require(Services.MapService)
local LootService = require(Services.LootService)
local CombatService = require(Services.CombatService)
local AbilityService = require(Services.AbilityService)

-- Phase 4 — orchestrator
local RoundService = require(Services.RoundService)

-- ── Initialise ────────────────────────────────────────────────────────────────

NetworkService.Init()
DataService.Init()

TeamService.Init()
ProgressionService.Init()

MapService.Init()
LootService.Init()
CombatService.Init()
AbilityService.Init()

RoundService.Init()

-- ── Start ─────────────────────────────────────────────────────────────────────

-- RoundService manages round-scoped ProgressionService event wiring internally.
-- Only permanent (non-round-scoped) wiring belongs here.

-- Sync profile to client after data loads
DataService.ProfileLoaded:Connect(function(player, profile)
	NetworkService.FireClient(require(ReplicatedStorage.Shared.Constants).NETWORK.PROFILE_SYNC, player, {
		Credits = profile.Credits,
		XP = profile.XP,
		Level = profile.Level,
		Statistics = profile.Statistics,
	})
end)

-- Start the round loop
RoundService.Start()

print("[Server] SPECops vs Robbers — server initialised.")
