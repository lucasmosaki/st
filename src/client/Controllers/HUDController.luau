--!strict
-- HUDController: creates and manages all ScreenGui elements.
-- Subscribes to other controllers' signals and updates the UI accordingly.
-- All GUI is created programmatically so no separate rbxm is required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Utility.Signal)

-- ── HUDController ─────────────────────────────────────────────────────────────

local HUDController = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- GUI references
local _screenGui: ScreenGui
local _ammoLabel: TextLabel
local _timerLabel: TextLabel
local _teamLabel: TextLabel
local _bagFrame: Frame
local _bagFill: Frame
local _bagLabel: TextLabel
local _interactFrame: Frame
local _interactFill: Frame
local _interactLabel: TextLabel
local _extractFrame: Frame
local _extractFill: Frame
local _notifFrame: Frame
local _notifLabel: TextLabel
local _winFrame: Frame
local _winLabel: TextLabel
local _rewardsFrame: Frame
local _rewardsLabel: TextLabel
local _crosshair: Frame
local _stateLabel: TextLabel

-- ── GUI Factory helpers ───────────────────────────────────────────────────────

local function makeFrame(parent: Instance, size: UDim2, pos: UDim2, bg: Color3?, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = bg or Color3.fromRGB(0, 0, 0)
	f.BackgroundTransparency = alpha or 0.5
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function makeLabel(parent: Instance, text: string, size: UDim2, pos: UDim2, fg: Color3?, fontSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.Text = text
	l.TextColor3 = fg or Color3.fromRGB(255, 255, 255)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = fontSize or 16
	l.Parent = parent
	return l
end

local function addCorner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
	return c
end

-- ── Build HUD ─────────────────────────────────────────────────────────────────

local function buildHUD()
	_screenGui = Instance.new("ScreenGui")
	_screenGui.Name = "GameHUD"
	_screenGui.ResetOnSpawn = false
	_screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	_screenGui.Parent = PlayerGui

	-- Crosshair
	local chSize = UDim2.new(0, 12, 0, 12)
	local chPos = UDim2.new(0.5, -6, 0.5, -6)
	_crosshair = makeFrame(_screenGui, chSize, chPos, Color3.new(1, 1, 1), 0)
	_crosshair.BackgroundTransparency = 1
	-- Four lines
	local function makeLine(w: number, h: number, ox: number, oy: number)
		local line = makeFrame(_crosshair,
			UDim2.new(0, w, 0, h),
			UDim2.new(0.5, -w/2 + ox, 0.5, -h/2 + oy),
			Color3.new(1, 1, 1),
			0
		)
		return line
	end
	makeLine(2, 8, 0, -7)
	makeLine(2, 8, 0, 7)
	makeLine(8, 2, -7, 0)
	makeLine(8, 2, 7, 0)

	-- Ammo display (bottom-right)
	local ammoPanel = makeFrame(_screenGui,
		UDim2.new(0, 120, 0, 40),
		UDim2.new(1, -130, 1, -55),
		Color3.fromRGB(0, 0, 0), 0.6
	)
	addCorner(ammoPanel, 8)
	_ammoLabel = makeLabel(ammoPanel, "30 / 30",
		UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 255, 255), 18
	)
	_ammoLabel.TextXAlignment = Enum.TextXAlignment.Center
	_ammoLabel.TextYAlignment = Enum.TextYAlignment.Center

	-- Round timer (top-centre)
	local timerPanel = makeFrame(_screenGui,
		UDim2.new(0, 120, 0, 36),
		UDim2.new(0.5, -60, 0, 10),
		Color3.fromRGB(0, 0, 0), 0.6
	)
	addCorner(timerPanel, 8)
	_timerLabel = makeLabel(timerPanel, "8:00",
		UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 220, 80), 22
	)
	_timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	_timerLabel.TextYAlignment = Enum.TextYAlignment.Center

	-- Team label (top-left)
	local teamPanel = makeFrame(_screenGui,
		UDim2.new(0, 120, 0, 30),
		UDim2.new(0, 10, 0, 10),
		Color3.fromRGB(0, 0, 0), 0.6
	)
	addCorner(teamPanel, 8)
	_teamLabel = makeLabel(teamPanel, "LOBBY",
		UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(200, 200, 200), 15
	)
	_teamLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- State label (below team)
	_stateLabel = makeLabel(_screenGui, "Lobby",
		UDim2.new(0, 150, 0, 24),
		UDim2.new(0, 10, 0, 45),
		Color3.fromRGB(180, 180, 180), 13
	)

	-- Bag weight bar (bottom-centre)
	local bagPanel = makeFrame(_screenGui,
		UDim2.new(0, 220, 0, 36),
		UDim2.new(0.5, -110, 1, -50),
		Color3.fromRGB(20, 20, 20), 0.55
	)
	addCorner(bagPanel, 8)
	_bagLabel = makeLabel(bagPanel, "Bag: 0 / 100",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 255, 255), 13
	)
	_bagLabel.TextXAlignment = Enum.TextXAlignment.Center
	local bagTrack = makeFrame(bagPanel,
		UDim2.new(1, -16, 0, 10),
		UDim2.new(0, 8, 1, -14),
		Color3.fromRGB(60, 60, 60), 0
	)
	addCorner(bagTrack, 5)
	_bagFill = makeFrame(bagTrack,
		UDim2.new(0, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 165, 0), 0
	)
	addCorner(_bagFill, 5)

	-- Interact progress (centre, appears when looting)
	_interactFrame = makeFrame(_screenGui,
		UDim2.new(0, 200, 0, 36),
		UDim2.new(0.5, -100, 0.65, 0),
		Color3.fromRGB(10, 10, 10), 0.5
	)
	addCorner(_interactFrame, 8)
	_interactFrame.Visible = false
	_interactLabel = makeLabel(_interactFrame, "Looting…",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 255, 255), 13
	)
	_interactLabel.TextXAlignment = Enum.TextXAlignment.Center
	local interTrack = makeFrame(_interactFrame,
		UDim2.new(1, -12, 0, 8),
		UDim2.new(0, 6, 1, -12),
		Color3.fromRGB(60, 60, 60), 0
	)
	addCorner(interTrack, 4)
	_interactFill = makeFrame(interTrack,
		UDim2.new(0, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(50, 200, 100), 0
	)
	addCorner(_interactFill, 4)

	-- Extraction progress (centre, full width)
	_extractFrame = makeFrame(_screenGui,
		UDim2.new(0, 260, 0, 44),
		UDim2.new(0.5, -130, 0.55, 0),
		Color3.fromRGB(10, 10, 10), 0.5
	)
	addCorner(_extractFrame, 10)
	_extractFrame.Visible = false
	makeLabel(_extractFrame, "EXTRACTING…",
		UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 215, 0), 15
	).TextXAlignment = Enum.TextXAlignment.Center
	local extTrack = makeFrame(_extractFrame,
		UDim2.new(1, -14, 0, 10),
		UDim2.new(0, 7, 1, -14),
		Color3.fromRGB(60, 60, 60), 0
	)
	addCorner(extTrack, 5)
	_extractFill = makeFrame(extTrack,
		UDim2.new(0, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 215, 0), 0
	)
	addCorner(_extractFill, 5)

	-- Notification (top-centre, temporary)
	_notifFrame = makeFrame(_screenGui,
		UDim2.new(0, 340, 0, 36),
		UDim2.new(0.5, -170, 0, 55),
		Color3.fromRGB(20, 20, 20), 0.4
	)
	addCorner(_notifFrame, 8)
	_notifFrame.Visible = false
	_notifLabel = makeLabel(_notifFrame, "",
		UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0),
		Color3.fromRGB(255, 255, 255), 14
	)

	-- Win/lose display (centre, big)
	_winFrame = makeFrame(_screenGui,
		UDim2.new(0, 400, 0, 100),
		UDim2.new(0.5, -200, 0.35, 0),
		Color3.fromRGB(0, 0, 0), 0.6
	)
	addCorner(_winFrame, 14)
	_winFrame.Visible = false
	_winLabel = makeLabel(_winFrame, "",
		UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(255, 255, 255), 32
	)
	_winLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- Rewards summary
	_rewardsFrame = makeFrame(_screenGui,
		UDim2.new(0, 340, 0, 130),
		UDim2.new(0.5, -170, 0.5, -65),
		Color3.fromRGB(15, 15, 15), 0.55
	)
	addCorner(_rewardsFrame, 12)
	_rewardsFrame.Visible = false
	_rewardsLabel = makeLabel(_rewardsFrame, "",
		UDim2.new(1, -20, 1, -10), UDim2.new(0, 10, 0, 5),
		Color3.fromRGB(255, 220, 80), 15
	)
	_rewardsLabel.TextXAlignment = Enum.TextXAlignment.Left
	_rewardsLabel.TextYAlignment = Enum.TextYAlignment.Top
end

-- ── Update helpers ────────────────────────────────────────────────────────────

local _notifTimer: thread? = nil

local function showNotification(message: string, notifType: string?)
	local color = if notifType == "Warning" then Color3.fromRGB(255, 180, 60)
		elseif notifType == "Error" then Color3.fromRGB(255, 80, 80)
		else Color3.fromRGB(80, 220, 120)

	_notifLabel.TextColor3 = color
	_notifLabel.Text = message
	_notifFrame.Visible = true
	_notifFrame.BackgroundTransparency = 0.4

	if _notifTimer then
		task.cancel(_notifTimer)
	end
	_notifTimer = task.delay(4, function()
		local tween = TweenService:Create(
			_notifFrame,
			TweenInfo.new(0.5),
			{ BackgroundTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Connect(function()
			_notifFrame.Visible = false
			_notifFrame.BackgroundTransparency = 0.4
		end)
	end)
end

local function updateBagBar(current: number, max: number)
	_bagLabel.Text = string.format("Bag: %d / %d", current, max)
	local pct = if max > 0 then current / max else 0
	_bagFill.Size = UDim2.new(pct, 0, 1, 0)
	-- Colour shift: green → yellow → red
	local r = math.min(1, pct * 2)
	local g = math.min(1, 2 - pct * 2)
	_bagFill.BackgroundColor3 = Color3.new(r, g, 0)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function HUDController.Init(
	CombatController: any,
	LootController: any,
	RoundController: any,
	AbilityController: any
)
	buildHUD()

	-- Ammo
	CombatController.AmmoChanged:Connect(function(current: number, max: number)
		_ammoLabel.Text = string.format("%d / %d", current, max)
		if current == 0 then
			_ammoLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		else
			_ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end)

	-- Round timer
	RoundController.TimerUpdated:Connect(function(remaining: number)
		_timerLabel.Text = RoundController.FormatTime(remaining)
		_timerLabel.TextColor3 = if remaining <= 30
			then Color3.fromRGB(255, 80, 80)
			else Color3.fromRGB(255, 220, 80)
	end)

	-- Team assignment
	RoundController.TeamAssigned:Connect(function(teamName: string)
		_teamLabel.Text = teamName:upper()
		_teamLabel.TextColor3 = if teamName == "Robbers"
			then Color3.fromRGB(255, 80, 80)
			else Color3.fromRGB(80, 140, 255)
	end)

	-- Round state
	RoundController.StateChanged:Connect(function(state: string, _data: any)
		_stateLabel.Text = state

		if state == "WinCondition" then
			-- shown by WinConditionResult
		elseif state == "Lobby" then
			_winFrame.Visible = false
			_rewardsFrame.Visible = false
			_timerLabel.Text = "--:--"
			_teamLabel.Text = "LOBBY"
			_bagFill.Size = UDim2.new(0, 0, 1, 0)
			_bagLabel.Text = "Bag: 0 / 100"
		end
	end)

	-- Win condition
	RoundController.WinConditionResult:Connect(function(data: any)
		local winner = data.WinningTeam or "?"
		local reason = data.WinReason or ""
		local LocalTeam = RoundController.GetTeam()
		local won = (LocalTeam == winner)

		_winLabel.Text = if won then "VICTORY!" else "DEFEAT"
		_winLabel.TextColor3 = if won
			then Color3.fromRGB(100, 255, 100)
			else Color3.fromRGB(255, 80, 80)
		_winFrame.Visible = true

		task.delay(8, function()
			_winFrame.Visible = false
		end)
	end)

	-- Notifications
	RoundController.NotificationReceived:Connect(function(data: any)
		if data and data.Message then
			showNotification(data.Message, data.Type)
		end
	end)

	-- Bag updates
	LootController.BagUpdated:Connect(function(bag: any)
		updateBagBar(bag.CurrentWeight, bag.MaxWeight)
	end)

	-- Interaction progress
	LootController.InteractionProgress:Connect(function(_nodeId: string, progress: number)
		if progress <= 0 then
			_interactFrame.Visible = false
		else
			_interactFrame.Visible = true
			_interactFill.Size = UDim2.new(progress, 0, 1, 0)
		end
	end)

	-- Extraction progress
	LootController.ExtractionProgress:Connect(function(data: any)
		if not data then return end
		local p = data.Progress or 0
		if p <= 0 then
			_extractFrame.Visible = false
		else
			_extractFrame.Visible = true
			_extractFill.Size = UDim2.new(p, 0, 1, 0)
		end
	end)

	-- Rewards summary
	RoundController.RewardsSummary:Connect(function(data: any)
		_winFrame.Visible = false
		_rewardsFrame.Visible = true
		_rewardsLabel.Text = string.format(
			"REWARDS\n+%d Credits\n+%d XP\nLevel: %d%s",
			data.CreditsEarned or 0,
			data.XPEarned or 0,
			data.NewLevel or 1,
			if (data.LevelsGained or 0) > 0
				then ("\nLevel Up ×" .. tostring(data.LevelsGained))
				else ""
		)
		task.delay(10, function()
			_rewardsFrame.Visible = false
		end)
	end)

	-- Nearby node prompt
	LootController.NearbyNodeChanged:Connect(function(node: any)
		if node then
			_interactLabel.Text = string.format("Press E — %s", node.LocationName or "Loot")
			_interactFrame.Visible = true
			_interactFill.Size = UDim2.new(0, 0, 1, 0)
		elseif not LootController.IsInteracting() then
			_interactFrame.Visible = false
		end
	end)
end

return HUDController
