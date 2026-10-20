------------------------------------------------------------------------
-- LTN console
------------------------------------------------------------------------

local tools = require('script.tools')
local RailCache = require('script.cache')

---@class ltn.Console
local Console = {}

---@param data CustomCommandData
local function list_refuel_excluded(data)
    local excluded_locos = { '' }

    for name, status in pairs(storage.ExcludedFromRefuel) do
        if status then
            local local_name = prototypes.entity[name] and prototypes.entity[name].localised_name or name
            excluded_locos[#excluded_locos + 1] = local_name
            excluded_locos[#excluded_locos + 1] = ', '
        end
    end
    if #excluded_locos > 1 then excluded_locos[#excluded_locos] = nil end

    tools.console(function() return { '', { 'console.ltn_command_list_refuel_excluded_msg' }, ' ', excluded_locos } end, data)
end

---@param data CustomCommandData
---@param text string
---@param network_id integer
local function list_network(data, text, network_id)
    ---@type ltn.TrainStop[]
    local stops = {}
    for stop_id, stop in pairs(storage.LogisticTrainStops) do
        if tools.isStopConsistent(stop) then
            if stop.network_id == network_id then
                stops[#stops + 1] = stop
            end
        else
            RemoveStop(stop_id)
        end
    end
    if #stops == 0 then
        tools.console(function() return { 'console.ltn_command_list_' .. text .. '_network_id_no', table_size(storage.LogisticTrainStops) } end, data)
    else
        tools.console(function() return { 'console.ltn_command_list_' .. text .. '_network_id_yes', #stops, table_size(storage.LogisticTrainStops) } end, data)

        local count = 0
        ---@type LocalisedString
        local msg
        for _, stop in pairs(stops) do
            if count % 10 == 0 then
                if count > 0 then tools.console(function() return msg end, data) end
                msg = { '' }
            end
            local stop_name = tools.richTextForStop(stop.entity)
            if stop_name then
                msg[#msg + 1] = stop_name
                count = count + 1
            end
        end
        if #msg > 1 then tools.console(function() return msg end, data) end
    end
end

---@param data CustomCommandData
local function list_default_network_id(data)
    return list_network(data, 'default', LtnSettings.default_network)
end

---@param data CustomCommandData
local function list_zero_network_id(data)
    return list_network(data, 'zero', 0)
end

---@param data CustomCommandData
local function route_cache_stats(data)
    local stats = RailCache.getStatistics()
    tools.console(function()
        return { 'console.ltn_command_route_cache_stats_msg', stats.size, stats.limit, stats.expired, stats.evicted }
    end, data)
end

function Console.registerCommands()
    commands.add_command('ltn-route-cache-stats', { 'console.ltn_command_route_cache_stats' }, route_cache_stats)
    commands.add_command('ltn-list-refuel-excluded', { 'console.ltn_command_list_refuel_excluded' }, list_refuel_excluded)
    commands.add_command('ltn-list-default-network-id', { 'console.ltn_command_list_default_network_id' }, list_default_network_id)
    commands.add_command('ltn-list-no-network-id', { 'console.ltn_command_list_zero_network_id' }, list_zero_network_id)
end

return Console
