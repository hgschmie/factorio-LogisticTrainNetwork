----------------------------------------------------------------------------------------
-- Rail Cache management
----------------------------------------------------------------------------------------

local tools = require('script.tools')
local Metrics = require('script.metrics')

---@class ltn.RailCache
local RailCache = {}

local EARLY_EXPIRATION_TICKS = 10
-- Spread a burst over roughly twelve early-cleanup passes.
local EXPIRATION_JITTER = 12 * EARLY_EXPIRATION_TICKS

---@param direction defines.rail_direction
---@param prefix string
local function metric_key(direction, prefix)
    return prefix .. (direction == defines.rail_direction.front and '_forward' or '_backward')
end

--- reset station distance lookup table
function RailCache.clear()
    storage.StopCache = {
        distances = {},
        expirations = {},
        metrics = Metrics.create(),
        expiration_cursor = nil,
    }
end

---@return ltn.StopCache stop_cache
local function get_cache()
    return assert(storage.StopCache)
end

---@param stop_distance ltn.StopDistance
local function unschedule(stop_distance)
    local cache = get_cache()
    local bucket = assert(cache.expirations[stop_distance.tick])
    local index = assert(stop_distance.expiration_index)
    local last_key = table.remove(bucket)

    if index <= #bucket then
        bucket[index] = last_key
        assert(cache.distances[last_key]).expiration_index = index
    end

    if #bucket == 0 then cache.expirations[stop_distance.tick] = nil end

    stop_distance.expiration_index = nil
end

---@param key ltn.EntityPairKey
---@param stop_distance ltn.StopDistance
---@param lifetime uint64
local function schedule(key, stop_distance, lifetime)
    if stop_distance.expiration_index then unschedule(stop_distance) end

    local cache = get_cache()

    local tick = game.tick + math.random(1, EXPIRATION_JITTER) + lifetime
    local bucket = cache.expirations[tick] or {}
    cache.expirations[tick] = bucket
    bucket[#bucket + 1] = key
    stop_distance.tick = tick
    stop_distance.expiration_index = #bucket

    -- A shorter lifetime can put a new deadline behind the pressure cursor.
    -- Next-tick placeholders will be handled by normal expiration instead.
    local cursor = cache.expiration_cursor
    if cursor and tick > game.tick + 1 and tick <= cursor then
        cache.expiration_cursor = tick - 1
    end
end

---@param key ltn.EntityPairKey
---@param stop_distance ltn.StopDistance
---@param reason 'expired'|'evicted'|nil
---@return boolean removed_entry True if an entry was removed
local function remove_distance(key, stop_distance, reason)
    unschedule(stop_distance)

    local cache = get_cache()
    local old_entry = cache.distances[key]
    cache.distances[key] = nil

    if not old_entry then return false end

    cache.metrics:dec('entries')
    -- UNKNOWN placeholders have no cached result to expire.
    if reason and (reason ~= 'expired' or stop_distance.distance ~= DISTANCE_RESULT.UNKNOWN) then
        cache.metrics:inc(reason)
    end

    return true
end

---@param tick uint64
---@param limit integer Stop deleting when this many entries remain.
local function expire_bucket(tick, limit)
    local cache = get_cache()
    local bucket = cache.expirations[tick]
    local reason = tick <= game.tick and 'expired' or 'evicted'

    while bucket and #bucket > 0 and cache.metrics:get('entries') > limit do
        local key = bucket[#bucket]
        remove_distance(key, assert(cache.distances[key]), reason)
    end
end

---@param event EventData.on_tick
function RailCache.onTick(event)
    expire_bucket(event.tick, 0)

    local cache = get_cache()

    if cache.metrics:get('entries') > LtnSettings.route_cache_size then
        local cursor = math.max(cache.expiration_cursor or event.tick, event.tick)
        for _ = 1, EARLY_EXPIRATION_TICKS do
            cursor = cursor + 1
            expire_bucket(cursor, LtnSettings.route_cache_size)
            if cache.metrics:get('entries') <= LtnSettings.route_cache_size then break end
        end
        cache.expiration_cursor = cursor
    end
    if cache.metrics:get('entries') <= LtnSettings.route_cache_size then
        cache.expiration_cursor = nil
    end
end

-- Independent of the dispatcher's configurable on_nth_tick registration.
script.on_event(defines.events.on_tick, RailCache.onTick)

---@param stop_id integer?
function RailCache.clearStopEntries(stop_id)
    if not stop_id then return end

    local cache = get_cache()

    for key, stop_distance in pairs(cache.distances) do
        if tools.matchPair(key, stop_id) then
            remove_distance(key, stop_distance)
        end
    end
end

---@return ltn.RouteCacheStatistics
function RailCache.getStatistics()
    local metrics = get_cache().metrics

    return {
        size = metrics:get('entries'),
        limit = LtnSettings.route_cache_size,
        expired = metrics:get('expired'),
        evicted = metrics:get('evicted'),
    }
end

---@param key ltn.EntityPairKey
---@return ltn.StopDistance
local function get_distance(key)
    local cache = get_cache()

    local stop_distance = cache.distances[key]
    if stop_distance and stop_distance.tick <= game.tick then
        remove_distance(key, stop_distance, 'expired')
        stop_distance = nil
    end
    if not stop_distance then
        stop_distance = { distance = DISTANCE_RESULT.UNKNOWN, tick = game.tick + 1 }
        cache.distances[key] = stop_distance
        cache.metrics:inc('entries')
        -- An unused UNKNOWN placeholder must not survive indefinitely.
        schedule(key, stop_distance, 1)
    end
    return stop_distance
end

---@class ltn.TrainMetrics: ltn.Metrics
---@field trains table<integer, ltn.Metrics>

---@param train_id integer
---@param all_train_metrics ltn.Metrics
---@param direction defines.rail_direction
function RailCache.updateUnreachable(train_id, all_train_metrics, direction)
    ---@cast all_train_metrics ltn.TrainMetrics
    local metrics = Metrics.create()
    metrics:set(metric_key(direction, 'unreachable'), 1)
    all_train_metrics:merge(metrics)
    if all_train_metrics.trains[train_id] then
        metrics:merge(all_train_metrics.trains[train_id])
    end
    all_train_metrics.trains[train_id] = metrics
end

--- Parse the StopDistance contents and special values and return the result and optional value
---@param stop_distance ltn.StopDistance?
---@return ltn.DistanceResult
---@return number? distance Returns nil if there is no result
local function parse_stop_distance(stop_distance)
    if not stop_distance then return DISTANCE_RESULT.UNREACHABLE, nil end

    local distance = (stop_distance.distance or 0)
    if distance == 0 then return DISTANCE_RESULT.UNREACHABLE, nil end

    -- on a different surface
    if distance == DISTANCE_RESULT.OTHER_SURFACE then return DISTANCE_RESULT.OTHER_SURFACE, nil end

    if distance > 0 then return DISTANCE_RESULT.PATH_AVAILABLE, distance end

    ---@cast distance ltn.DistanceResult
    return distance, nil
end

--- Returns true if a free train has a distance for the requested path. Otherwise, add the train
--- to the computation list unless it is marked as unreachable.
---@param stop_distance ltn.StopDistance
---@param free_train ltn.FreeTrain
---@param free_trains ltn.FreeTrain[]
---@param rail_ends RailEndStart[]
---@param direction defines.rail_direction
---@param cache_metrics ltn.Metrics
---@param all_train_metrics ltn.Metrics
---@return boolean is_selected
function RailCache:selectFreeTrain(stop_distance, free_train, free_trains, rail_ends, direction, cache_metrics, all_train_metrics)
    local distance_result, distance = parse_stop_distance(stop_distance)

    if distance_result == DISTANCE_RESULT.PATH_AVAILABLE then
        cache_metrics:inc(metric_key(direction, 'cached'))
        if not free_train.provider_distance or free_train.provider_distance > distance then
            free_train.provider_distance = distance
        end
        return true
    else
        if distance_result == DISTANCE_RESULT.UNKNOWN then cache_metrics:inc(metric_key(direction, 'unknown')) end
        if distance_result == DISTANCE_RESULT.UNREACHABLE then
            cache_metrics:inc(metric_key(direction, 'unreachable'))
            self.updateUnreachable(free_train.train.id, all_train_metrics, direction)
        else
            cache_metrics:inc(metric_key(direction, 'compute'))
            local rail_end = free_train.train.get_rail_end(direction)
            rail_ends[#rail_ends + 1] = {
                allow_path_within_segment = false,
                direction = rail_end.direction,
                rail = rail_end.rail,
            }
            free_trains[#free_trains + 1] = free_train
        end
    end
    return false
end

--- Always returns a result that is a reference into storage so modifying the
--- the result changes all references to it.
---@param train LuaTrain
---@param to LuaEntity
---@return ltn.StopDistance front_distance
---@return ltn.StopDistance back_distance
function RailCache.getCachedDistance(train, to)
    local front_rail_id = train.front_end.rail.unit_number
    ---@cast front_rail_id -?
    local back_rail_id = train.back_end.rail.unit_number
    ---@cast back_rail_id -?

    local front_stop_pair = tools.sortedPair(front_rail_id, to.unit_number, tonumber(train.front_end.direction))
    local back_stop_pair = tools.sortedPair(back_rail_id, to.unit_number, tonumber(train.back_end.direction))

    local front_stop_distance = get_distance(front_stop_pair)
    local back_stop_distance = get_distance(back_stop_pair)
    return front_stop_distance, back_stop_distance
end

---@param stop_distance ltn.StopDistance
---@param distance number?
function RailCache.updateDistance(stop_distance, distance)
    local index = stop_distance.expiration_index
    if not index then return end

    local cache = get_cache()

    local bucket = cache.expirations[stop_distance.tick]
    local key = bucket and bucket[index]
    -- A reference retained across removal must not reinsert an obsolete entry.
    if not key or cache.distances[key] ~= stop_distance then return end
    -- add some jitter to the lifetime so that not all entries expire at the same time
    stop_distance.distance = distance
    schedule(key, stop_distance, LtnSettings.route_cache_lifetime)
end

return RailCache
