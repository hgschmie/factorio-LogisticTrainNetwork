----------------------------------------------------------------------------------------
-- Rail Cache management
----------------------------------------------------------------------------------------

local tools = require('script.tools')
local Metrics = require('script.metrics')

---@class ltn.RailCache
local RailCache = {}

---@param direction defines.rail_direction
---@param prefix string
local function metric_key(direction, prefix)
    return prefix .. (direction == defines.rail_direction.front and '_forward' or '_backward')
end

--- reset station distance lookup table
function RailCache.clear()
    storage.StopDistances = {}
end

---@param stop_id integer?
function RailCache.clearStopEntries(stop_id)
    if not stop_id then return end

    for key in pairs(storage.StopDistances) do
        if tools.matchPair(key, stop_id) then
            storage.StopDistances[key] = nil
        end
    end
end

---@param train_id integer
---@param all_train_metrics ltn.Metrics
---@param direction defines.rail_direction
function RailCache.updateUnreachable(train_id, all_train_metrics, direction)
    local metrics = Metrics.create()
    metrics:set(metric_key(direction, 'unreachable'), 1)
    all_train_metrics:merge(metrics)
    ---@diagnostic disable-next-line: cast-type-mismatch
    ---@cast all_train_metrics.trains table<integer, ltn.Metrics>
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
            free_train.provider_distance  = distance
        end
        return true
    else
        if distance_result == DISTANCE_RESULT.UNKNOWN then cache_metrics:inc(metric_key(direction, 'unknown')) end
        if distance_result == DISTANCE_RESULT.EXPIRED then cache_metrics:inc(metric_key(direction, 'expired')) end
        if distance_result == DISTANCE_RESULT.UNREACHABLE then
            cache_metrics:inc(metric_key(direction, 'unreachable'))
            self.updateUnreachable(free_train.train.id, all_train_metrics, direction)
        else
            cache_metrics:inc(metric_key(direction, 'compute'))
            local rail_end = free_train.train.get_rail_end(direction)
            rail_ends[#rail_ends + 1] = {
                allow_path_within_segment = false,
                direction = rail_end.direction,
                rail = rail_end.rail
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

    local front_stop_distance = storage.StopDistances[front_stop_pair]

    if not front_stop_distance or type(front_stop_distance) ~= 'table' then
        front_stop_distance = {
            distance = DISTANCE_RESULT.UNKNOWN,
            tick = game.tick,
        }

        storage.StopDistances[front_stop_pair] = front_stop_distance
    end

    if not front_stop_distance.tick or (front_stop_distance.tick < game.tick) then
        front_stop_distance.tick = nil
        front_stop_distance.distance = DISTANCE_RESULT.EXPIRED
    end

    local back_stop_distance = storage.StopDistances[back_stop_pair]
    if not back_stop_distance or type(back_stop_distance) ~= 'table' then
        back_stop_distance = {
            distance = DISTANCE_RESULT.UNKNOWN,
            tick = game.tick,
        }

        storage.StopDistances[back_stop_pair] = back_stop_distance
    end

    if not back_stop_distance.tick or (back_stop_distance.tick < game.tick) then
        back_stop_distance.tick = nil
        back_stop_distance.distance = DISTANCE_RESULT.EXPIRED
    end

    return front_stop_distance, back_stop_distance
end

---@param stop_distance ltn.StopDistance
---@param distance number?
function RailCache.updateDistance(stop_distance, distance)
    -- add some jitter to the lifetime so that not all entries expire at the same time
    stop_distance.tick = game.tick + LtnSettings.route_cache_lifetime + math.random(1, 120)
    stop_distance.distance = distance
end

return RailCache
