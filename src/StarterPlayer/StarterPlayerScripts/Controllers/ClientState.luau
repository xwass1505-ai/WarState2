-- ClientState: read-only mirror of the server-authoritative country snapshot.
-- The client NEVER edits gameplay state here; it only displays what the server sent.

local ClientState = {}

local listeners = {}
ClientState.snapshot = { Active = false }

function ClientState.set(snapshot)
	ClientState.snapshot = snapshot or { Active = false }
	for _, fn in ipairs(listeners) do
		task.spawn(fn, ClientState.snapshot)
	end
end

function ClientState.onChanged(fn)
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

return ClientState
