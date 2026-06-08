--!strict
-- Shared type definitions for SPECops vs Robbers

export type TeamType = "Robbers" | "SPECops" | "Lobby"

export type RoundState =
	| "Lobby"
	| "Intermission"
	| "MapVoting"
	| "MapLoading"
	| "TeamAssignment"
	| "Preparation"
	| "ActiveRound"
	| "WinCondition"
	| "Rewards"
	| "Cleanup"

export type WinReason =
	| "RobbersExtracted"
	| "RobbersLootTarget"
	| "AllRobbersEliminated"
	| "TimerExpired"

export type WeaponFireMode = "Automatic" | "SemiAutomatic" | "Shotgun"

export type WeaponData = {
	Name: string,
	DisplayName: string,
	FireMode: WeaponFireMode,
	Damage: number,
	HeadshotMultiplier: number,
	FireRate: number, -- shots per second
	MagazineSize: number,
	ReloadTime: number,
	RecoilX: number,
	RecoilY: number,
	Spread: number, -- degrees
	PelletsPerShot: number,
	FalloffStart: number,
	FalloffEnd: number,
	FalloffMin: number,
	MaxRange: number,
	AllowedTeams: { TeamType },
}

export type AbilityActivationType = "Active" | "Passive"

export type AbilityData = {
	Id: string,
	Name: string,
	Description: string,
	ActivationType: AbilityActivationType,
	Cooldown: number,
	Charges: number,
	Duration: number,
	Icon: string,
	Team: TeamType,
}

export type LootItemData = {
	Id: string,
	Name: string,
	DisplayName: string,
	Value: number,
	Weight: number,
	InteractionTime: number,
}

export type LootNodeConfig = {
	Id: string,
	LocationName: string,
	Position: Vector3,
	LootPool: { string },
	MaxItemsSpawned: number,
	RespawnTime: number,
}

export type MapConfig = {
	Id: string,
	DisplayName: string,
	MinPlayers: number,
	MaxPlayers: number,
	RoundDuration: number,
	PreparationDuration: number,
	RobberSpawns: { CFrame },
	SPECopsSpawns: { CFrame },
	LootNodes: { LootNodeConfig },
	ExtractionZones: { { Position: Vector3, Radius: number } },
	TotalLootValue: number,
	Description: string,
	ThumbnailId: string,
}

export type PlayerProfile = {
	Credits: number,
	XP: number,
	Level: number,
	Statistics: PlayerStatistics,
	Unlocks: { string },
	PurchasedCosmetics: { string },
	LoadoutSlots: { PlayerLoadout },
	RobberWeight: number,
	LastRoleWasRobber: boolean,
	DailyChallenges: { DailyChallenge },
	_version: number,
}

export type PlayerStatistics = {
	GamesPlayed: number,
	GamesWon: number,
	LootValueStolen: number,
	Kills: number,
	Deaths: number,
	ShotsFired: number,
	ShotsHit: number,
	ExtractionSuccesses: number,
	TimePlayedSeconds: number,
}

export type PlayerLoadout = {
	PrimaryWeapon: string,
	SecondaryWeapon: string,
	ActiveAbility: string,
	PassiveAbility1: string,
	PassiveAbility2: string,
}

export type DailyChallenge = {
	Id: string,
	Name: string,
	Description: string,
	Requirement: number,
	Progress: number,
	CreditReward: number,
	XPReward: number,
	Completed: boolean,
	ExpiresAt: number,
}

export type HitPayload = {
	WeaponName: string,
	TargetUserId: number,
	HitPart: string,
	Distance: number,
	Origin: Vector3,
	Direction: Vector3,
	Timestamp: number,
}

export type RoundSummary = {
	WinningTeam: TeamType,
	WinReason: WinReason,
	Duration: number,
	LootExtracted: number,
	TopPlayers: { { UserId: number, Score: number } },
}

export type LootNodeState = {
	Id: string,
	LocationName: string,
	Position: Vector3,
	Items: { { ItemId: string, Active: boolean } },
	RespawnAt: number?,
}

export type BagState = {
	CurrentWeight: number,
	MaxWeight: number,
	Items: { { ItemId: string, Count: number, Value: number } },
}

export type ExtractionState = {
	IsActive: boolean,
	Progress: number, -- 0 to 1
	ExtractingPlayer: number?, -- UserId
	ZoneIndex: number,
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

return {}
