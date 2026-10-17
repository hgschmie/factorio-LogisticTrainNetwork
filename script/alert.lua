--[[ Copyright (c) 2020 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

---@type table<string, SignalID>
local icons = {
    ['cargo-warning'] = { type = 'virtual', name = 'ltn-cargo-warning', quality = 'normal', },
    ['cargo-alert'] = { type = 'virtual', name = 'ltn-cargo-alert', quality = 'normal', },
    ['depot-warning'] = { type = 'virtual', name = 'ltn-depot-warning', quality = 'normal', },
    ['depot-empty'] = { type = 'virtual', name = 'ltn-depot-empty', quality = 'normal', },
}

---@param entity LuaEntity
---@param icon ltn.AlertType
---@param msg LocalisedString
---@param force LuaForce?
function create_alert(entity, icon, msg, force)
    force = force or (entity and entity.force)
    if not force or not force.valid then
        return
    end

    assert(icons[icon])

    for player_index, player in pairs(force.players) do
        if player.valid and LtnSettings.get_player_settings(player_index).factorio_alerts then
            player.add_custom_alert(entity, icons[icon], msg, true)
        end
    end
end
