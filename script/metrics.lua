-----------------------------------------------------------------------
-- metrics collector
-----------------------------------------------------------------------

--- A metrics collector. Holds the metric values directly as key/value
--- pairs, so it can be iterated with pairs(). The accessor methods live
--- on the metatable and are not part of the iteration.
---
---@class ltn.Metrics: { [string]: integer }
local Metrics = {}

Metrics.__index = Metrics

--- Sets a metric to a given value. Creates the metric if it does not exist yet.
---
---@param key string
---@param value integer
function Metrics:set(key, value)
    rawset(self, key, value)
end

--- Increments a metric by one. Creates the metric with a value of 1 if it does not exist yet.
---
---@param key string
---@return integer value The new value of the metric.
function Metrics:inc(key)
    local value = (rawget(self, key) or 0) + 1
    rawset(self, key, value)
    return value
end

---Decrementss a metric by one if it exists. Does not decrement below 0.
---
---@param key string
---@return integer value The new value of the metric.
function Metrics:dec(key)
    local value = rawget(self, key)
    value = (not value or value == 0) and 0 or (value - 1)
    rawset(self, key, value)
    return value
end

--- Merges another collector into this one. Metrics present in both are added up.
---
---@param other ltn.Metrics
function Metrics:merge(other)
    for key, value in pairs(other) do
        rawset(self, key, (rawget(self, key) or 0) + value)
    end
end

--- Creates a new, empty metrics collector.
---
---@return ltn.Metrics
function Metrics.create()
    return setmetatable({}, Metrics)
end

return Metrics
