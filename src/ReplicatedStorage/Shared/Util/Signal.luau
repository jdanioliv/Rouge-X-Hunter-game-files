-- Minimal signal implementation for decoupling services
-- (e.g. PlayerStateService fires PlayerDowned, CombatService reacts).

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

function Signal.new()
	return setmetatable({
		_handlers = {},
	}, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local handlers = self._handlers
	table.insert(handlers, handler)

	local connection = {}
	function connection:Disconnect()
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Clone so handlers that disconnect during iteration don't skip entries.
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal
