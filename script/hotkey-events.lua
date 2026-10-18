--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 * Handle hotkey events
 *
 * See LICENSE.md in the project directory for license information.
--]]

local tools = require('script.tools')

---@param event EventData.CustomInputEvent
local function handle_ltn_toggle_dispatcher(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local enabled = LtnSettings.dispatcher_enabled
    settings.global['ltn-dispatcher-enabled'] = { value = not enabled }
    tools.printmsg(0, function()
        return { enabled and 'ltn-message.dispatcher-disabled' or 'ltn-message.dispatcher-enabled', player.name }
    end)
end

script.on_event('ltn-toggle-dispatcher', handle_ltn_toggle_dispatcher)
