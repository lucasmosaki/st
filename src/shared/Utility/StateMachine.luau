--!strict
-- Finite State Machine used by RoundService.
-- Supports guarded transitions, OnEnter/OnExit callbacks, and change signals.

local Signal = require(script.Parent.Signal)

export type StateConfig = {
	Transitions: { string }?,  -- nil = unrestricted
	OnEnter: ((prev: string, ...any) -> ())?,
	OnExit: ((next: string) -> ())?,
}

export type StateMachine = {
	State: string,
	PreviousState: string?,
	StateChanged: Signal.Signal<string, string>,
	CanTransition: (self: StateMachine, target: string) -> boolean,
	To: (self: StateMachine, target: string, ...any) -> boolean,
	Destroy: (self: StateMachine) -> (),
}

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(initial: string, states: { [string]: StateConfig }): StateMachine
	assert(states[initial], "[FSM] Initial state not defined: " .. initial)

	local self = setmetatable({
		State = initial,
		PreviousState = nil :: string?,
		StateChanged = Signal.new() :: Signal.Signal<string, string>,
		_states = states,
	}, StateMachine)

	return self :: any
end

function StateMachine:CanTransition(target: string): boolean
	local cfg = self._states[self.State]
	if not cfg then
		return false
	end
	if not cfg.Transitions then
		return self._states[target] ~= nil
	end
	for _, allowed in cfg.Transitions do
		if allowed == target then
			return true
		end
	end
	return false
end

function StateMachine:To(target: string, ...: any): boolean
	if not self._states[target] then
		warn(("[FSM] Unknown state: %s"):format(target))
		return false
	end
	if not self:CanTransition(target) then
		warn(("[FSM] Blocked transition: %s → %s"):format(self.State, target))
		return false
	end

	local prev = self.State
	local prevCfg = self._states[prev]

	if prevCfg and prevCfg.OnExit then
		local ok, err = pcall(prevCfg.OnExit, target)
		if not ok then
			warn("[FSM] OnExit error: " .. tostring(err))
		end
	end

	self.PreviousState = prev
	self.State = target

	local nextCfg = self._states[target]
	if nextCfg and nextCfg.OnEnter then
		local ok, err = pcall(nextCfg.OnEnter, prev, ...)
		if not ok then
			warn("[FSM] OnEnter error: " .. tostring(err))
		end
	end

	self.StateChanged:Fire(target, prev)
	return true
end

function StateMachine:Destroy()
	self.StateChanged:DisconnectAll()
end

return StateMachine
