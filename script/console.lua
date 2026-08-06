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

function Console:registerCommands()
    commands.add_command('ltn-list-refuel-excluded', { 'console.ltn_command_list_refuel_excluded' }, list_refuel_excluded)
end

return Console
