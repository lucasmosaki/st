--!strict
-- NetworkService: creates and provides access to all RemoteEvents/Functions.
-- Must be Init()ed before any other service fires remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

-- ── NetworkService ────────────────────────────────────────────────────────────

local NetworkService = {}

local _remoteFolder: Folder
local _events: { [string]: RemoteEvent } = {}
local _functions: { [string]: RemoteFunction } = {}

-- Names that should be RemoteFunctions instead of RemoteEvents
local FUNCTION_NAMES: { [string]: boolean } = {
	-- (none needed for current design; expand as required)
}

function NetworkService.Init()
	_remoteFolder = Instance.new("Folder")
	_remoteFolder.Name = "Remotes"
	_remoteFolder.Parent = ReplicatedStorage

	for _, name in Constants.NETWORK do
		if FUNCTION_NAMES[name] then
			local rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = _remoteFolder
			_functions[name] = rf
		else
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = _remoteFolder
			_events[name] = re
		end
	end
end

-- Fire a RemoteEvent to one client
function NetworkService.FireClient(name: string, player: Player, ...: any)
	local re = _events[name]
	if not re then
		warn("[NetworkService] Unknown remote:", name)
		return
	end
	re:FireClient(player, ...)
end

-- Fire a RemoteEvent to all clients
function NetworkService.FireAllClients(name: string, ...: any)
	local re = _events[name]
	if not re then
		warn("[NetworkService] Unknown remote:", name)
		return
	end
	re:FireAllClients(...)
end

-- Fire a RemoteEvent to all clients except one
function NetworkService.FireAllClientsExcept(name: string, except: Player, ...: any)
	local re = _events[name]
	if not re then
		warn("[NetworkService] Unknown remote:", name)
		return
	end
	for _, player in game:GetService("Players"):GetPlayers() do
		if player ~= except then
			re:FireClient(player, ...)
		end
	end
end

-- Fire to a team
function NetworkService.FireTeam(name: string, teamName: string, ...: any)
	local re = _events[name]
	if not re then
		warn("[NetworkService] Unknown remote:", name)
		return
	end
	local Players = game:GetService("Players")
	local Teams = game:GetService("Teams")
	local team = Teams:FindFirstChild(teamName) :: Team?
	if not team then
		return
	end
	for _, player in Players:GetPlayers() do
		if player.Team == team then
			re:FireClient(player, ...)
		end
	end
end

-- Register a server-side listener for a RemoteEvent
function NetworkService.OnClientEvent(name: string, fn: (player: Player, ...any) -> ())
	local re = _events[name]
	if not re then
		warn("[NetworkService] Unknown remote:", name)
		return
	end
	re.OnServerEvent:Connect(fn)
end

-- Register a server-side handler for a RemoteFunction
function NetworkService.OnClientInvoke(name: string, fn: (player: Player, ...any) -> ...any)
	local rf = _functions[name]
	if not rf then
		warn("[NetworkService] Unknown RemoteFunction:", name)
		return
	end
	rf.OnServerInvoke = fn
end

function NetworkService.GetFolder(): Folder
	return _remoteFolder
end

return NetworkService
