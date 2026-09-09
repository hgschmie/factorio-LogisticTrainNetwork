------------------------------------------------------------------------
-- LTN console
------------------------------------------------------------------------

local tools = require('script.tools')

---@class ltn.Console
local Console = {}

---@param data CustomCommandData
local function list_refuel_excluded(data)
    local player = game.players[data.player_index]
    local excluded_locos = { '' }

    for name, status in pairs(storage.ExcludedFromRefuel) do
        if status then
            local local_name = prototypes.entity[name] and prototypes.entity[name].localised_name or name
            excluded_locos[#excluded_locos + 1] = local_name
            excluded_locos[#excluded_locos + 1] = ', '
        end
    end
    excluded_locos[#excluded_locos] = nil

    tools.printmsg(0, function() return { '', { 'console.ltn_command_list_refuel_excluded_msg' }, ' ', excluded_locos } end, player)
end

---@param data CustomCommandData
---@param text string
---@param network_id integer
local function list_network(data, text, network_id)
    local player = game.players[data.player_index]
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
        tools.printmsg(0, function() return { 'console.ltn_command_list_' .. text .. '_network_id_no', table_size(storage.LogisticTrainStops) } end, player)
    else
        tools.printmsg(0, function() return { 'console.ltn_command_list_' .. text .. '_network_id_yes', #stops, table_size(storage.LogisticTrainStops) } end, player)

        local count = 0
        local msg
        for _, stop in pairs(stops) do
            if count % 10 == 0 then
                if count > 0 then tools.printmsg(0, function() return msg end, player) end
                msg= {''}
            end
            msg[#msg + 1] = tools.richTextForStop(stop.entity)
            count = count + 1
        end
        if #msg > 1 then tools.printmsg(0, function() return msg end, player) end
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

function Console:registerCommands()
    commands.add_command('ltn-list-refuel-excluded', { 'console.ltn_command_list_refuel_excluded' }, list_refuel_excluded)
    commands.add_command('ltn-list-default-network-id', { 'console.ltn_command_list_default_network_id' }, list_default_network_id)
    commands.add_command('ltn-list-no-network-id', { 'console.ltn_command_list_zero_network_id' }, list_zero_network_id)
end

return Console
