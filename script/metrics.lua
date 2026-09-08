-----------------------------------------------------------------------
-- metrics collector
-----------------------------------------------------------------------

--- A metrics collector. Holds the metric values directly as key/value
--- pairs, so it can be iterated with pairs(). The accessor methods live
--- on the metatable and are not part of the iteration.
---
---@class ltn.Metrics: { [string]: integer }
local Metrics = {}

Metrics.PROCESS_REQUEST_METRICS = {
    'no_matching_network',
    'stop_is_full',
    'no_train_available',
    'only_cargo_wagons',
    'only_fluid_wagons',
    'empty_train',
    'unreachable',
    'different_surface',
    'different_force',
    'provider_min_too_long',
    'provider_max_too_short',
    'train_too_short',
    'train_too_long',
    'train_invalid',
    'invalid_stop',
}

Metrics.CACHE_METRICS = {
    'cached_result',
    'compute_forward',
    'unknown_forward',
    'expired_forward',
    'unreachable_forward',
    'compute_backward',
    'unknown_backward',
    'expired_backward',
    'unreachable_backward',
    'other_surface',
    'unreachable',
}

Metrics.__index = Metrics

--- Sets a metric to a given value. Creates the metric if it does not exist yet.
---
---@param key string
---@param value integer
function Metrics:set(key, value)
    rawset(self, key, value)
end

--- Gets a metric value.
---@param key string
---@return integer value
function Metrics:get(key)
    return rawget(self, key) or 0
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

---@param result_collector any[]
---@param metrics_key string
---@return any[] result_collector
function Metrics:add_metric(result_collector, metrics_key)
    local metrics_value = rawget(self, metrics_key)
    if metrics_value and (metrics_value > 0) then
        result_collector[#result_collector + 1] = { 'metrics.' .. metrics_key }
        result_collector[#result_collector + 1] = tostring(metrics_value) .. ', '
    end

    return result_collector
end

---@param result_collector any[]
---@param metrics_names string
---@return any[] result_collector
function Metrics:summarize(result_collector, metrics_names)
    local metrics_keys = assert(Metrics[metrics_names]) --[[@as string[] ]]
    for _, metrics_key in pairs(metrics_keys) do
        self:add_metric(result_collector, metrics_key)
    end
    if #result_collector > 1 then
        result_collector[#result_collector] = result_collector[#result_collector]:sub(1, #result_collector[#result_collector] - 2)
    end

    return result_collector
end

--- Creates a new, empty metrics collector.
---
---@return ltn.Metrics
function Metrics.create()
    return setmetatable({}, Metrics)
end

return Metrics
