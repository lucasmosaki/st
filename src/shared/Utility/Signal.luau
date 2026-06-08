--!strict
-- High-performance signal (event) implementation.
-- Uses a free-thread pool to avoid coroutine allocation on every Fire().

local FreeThread: thread? = nil

local function runCallback(fn: (...any) -> (), ...: any)
	local thread = FreeThread
	FreeThread = nil
	fn(...)
	FreeThread = thread
end

local function yieldForever()
	while true do
		runCallback(coroutine.yield())
	end
end

-- ── Connection ────────────────────────────────────────────────────────────────

local Connection = {}
Connection.__index = Connection

export type Connection = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		_signal: any,
		_fn: (...any) -> (),
		_next: Connection | false,
	},
	Connection
))

function Connection.new(signal: any, fn: (...any) -> ()): Connection
	return setmetatable({
		Connected = true,
		_signal = signal,
		_fn = fn,
		_next = false,
	}, Connection) :: any
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local s = self._signal
	if s._head == self then
		s._head = self._next
	else
		local node = s._head
		while node and node ~= false do
			if node._next == self then
				node._next = self._next
				break
			end
			node = node._next
		end
	end
end

-- ── Signal ────────────────────────────────────────────────────────────────────

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _head = false :: Connection | false }, Signal) :: any
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local conn = Connection.new(self, fn)
	if self._head then
		conn._next = self._head
	end
	self._head = conn
	return conn
end

function Signal:Once(fn: (...any) -> ()): Connection
	local conn: Connection
	conn = self:Connect(function(...)
		if conn.Connected then
			conn:Disconnect()
		end
		fn(...)
	end)
	return conn
end

function Signal:Fire(...: any)
	local node = self._head
	while node and node ~= false do
		if node.Connected then
			if not FreeThread then
				FreeThread = coroutine.create(yieldForever)
				coroutine.resume(FreeThread :: thread, node._fn, ...)
			else
				task.spawn(node._fn, ...)
			end
		end
		node = node._next
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	local conn: Connection
	conn = self:Connect(function(...)
		conn:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	self._head = false
end

return Signal
