-----------------------------------------------------------------------
-- tools
-----------------------------------------------------------------------

---@class ltn.Tools
local Tools = {}

--- Typed access to the dispatcher instance from storage.
---
---@return ltn.Dispatcher
function Tools.getDispatcher()
    return storage.Dispatcher
end

--- Convert a Signal into a typed item string
---@param signal SignalID
---@return ltn.ItemIdentifier
function Tools.createItemIdentifier(signal)
    assert(signal)
    return (signal.type or 'item')
        .. ',' .. signal.name
    -- .. ',' .. (signal.quality or 'normal')
end

return Tools
