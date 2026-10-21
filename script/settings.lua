--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 * localizes and converts global runtime settings
 *
 * See LICENSE.md in the project directory for license information.
--]]

local tools = require('script.tools')

---@enum ltn.DepotTrainLimit
ltn_depot_train_limit = {
    reset = 0,
    set_one = 1,
    unchanged = 2,
}

---@class ltn.PlayerSettings
---@field console_messages boolean
---@field factorio_alerts boolean

---@type table<integer, ltn.PlayerSettings>
local player_settings = {}

---@class ltn.Settings
---@field message_level integer
---@field debug_log integer?
---@field message_include_gps boolean
---@field delivery_timeout integer
---@field depot_inactivity integer
---@field dispatcher_enabled boolean
---@field finish_loading boolean
---@field dispatcher_nth_tick integer
---@field min_provided integer
---@field requester_delivery_reset boolean
---@field min_requested integer
---@field schedule_cc boolean
---@field stop_timeout integer
---@field dispatcher_updates_per_tick integer
---@field dispatcher_stop_updates_per_tick integer
---@field route_cache_lifetime integer
---@field route_cache_size integer
---@field depot_reset_filters boolean
---@field depot_fluid_cleaning number
---@field default_network integer
---@field provider_show_existing_cargo boolean
---@field requester_ignores_trains boolean
---@field enable_fuel_stations boolean
---@field use_fuel_station_interrupt boolean
---@field reset_interrupts boolean
---@field reselect_depot boolean
---@field advanced_cross_surface_delivery boolean
---@field depot_fudge_factor integer
---@field depot_limit_trains ltn.DepotTrainLimit
---@field limit_eligible_trains integer
---@field get_player_settings fun(player_index: integer): ltn.PlayerSettings
---@diagnostic disable-next-line: missing-fields
LtnSettings = LtnSettings or {}

---@param x ModSetting?
---@return double value
local function setting_number(x)
    assert(x)
    return assert(tonumber(x.value))
end

---@param x ModSetting?
---@return integer value
local function setting_int(x)
    return math.floor(setting_number(x))
end

---@param x ModSetting?
---@return boolean value
local function setting_bool(x)
    assert(x)
    return x.value and true or false
end

---@alias ltn.SettingFunction fun(ltn_settings: ltn.Settings, name: string): boolean?
---@alias ltn.PlayerSettingFunction fun(ltn_player_settings: ltn.PlayerSettings, name: string, player_index: integer): boolean?

---@type table<string, ltn.SettingFunction>
local change_settings = {
    ['ltn-interface-console-level'] = function(ltn_settings, name) ltn_settings.message_level = setting_int(settings.global[name]) end,
    ['ltn-interface-message-gps'] = function(ltn_settings, name) ltn_settings.message_include_gps = setting_bool(settings.global[name]) end,
    ['ltn-interface-debug-logfile'] = function(ltn_settings, name)
        local value = setting_int(settings.global[name])
        ltn_settings.debug_log = value > 0 and value or nil
    end,
    ['ltn-dispatcher-requester-threshold'] = function(ltn_settings, name) ltn_settings.min_requested = setting_int(settings.global[name]) end,
    ['ltn-dispatcher-provider-threshold'] = function(ltn_settings, name) ltn_settings.min_provided = setting_int(settings.global[name]) end,
    ['ltn-dispatcher-schedule-circuit-control'] = function(ltn_settings, name) ltn_settings.schedule_cc = setting_bool(settings.global[name]) end,
    ['ltn-dispatcher-depot-inactivity'] = function(ltn_settings, name) ltn_settings.depot_inactivity = setting_int(settings.global[name]) * 60 end,
    ['ltn-dispatcher-stop-timeout'] = function(ltn_settings, name) ltn_settings.stop_timeout = setting_int(settings.global[name]) * 60 end,
    ['ltn-dispatcher-delivery-timeout'] = function(ltn_settings, name) ltn_settings.delivery_timeout = setting_int(settings.global[name]) * 60 end,
    ['ltn-dispatcher-finish-loading'] = function(ltn_settings, name) ltn_settings.finish_loading = setting_bool(settings.global[name]) end,
    ['ltn-dispatcher-requester-delivery-reset'] = function(ltn_settings, name) ltn_settings.requester_delivery_reset = setting_bool(settings.global[name]) end,
    ['ltn-dispatcher-enabled'] = function(ltn_settings, name) ltn_settings.dispatcher_enabled = setting_bool(settings.global[name]) end,
    ['ltn-dispatcher-nth_tick'] = function(ltn_settings, name)
        ltn_settings.dispatcher_nth_tick = setting_int(settings.global[name])
        return true -- reconfigure the ticker
    end,
    ['ltn-dispatcher-updates-per-tick'] = function(ltn_settings, name) ltn_settings.dispatcher_updates_per_tick = setting_int(settings.global[name]) end,
    ['ltn-dispatcher-stop-updates-per-tick'] = function(ltn_settings, name) ltn_settings.dispatcher_stop_updates_per_tick = setting_int(settings.global[name]) end,
    ['ltn-dispatcher-route-cache-lifetime'] = function(ltn_settings, name) ltn_settings.route_cache_lifetime = setting_int(settings.global[name]) * 3600 end,
    ['ltn-dispatcher-route-cache-size'] = function(ltn_settings, name) ltn_settings.route_cache_size = setting_int(settings.startup[name]) end,
    ['ltn-depot-reset-filters'] = function(ltn_settings, name) ltn_settings.depot_reset_filters = setting_bool(settings.global[name]) end,
    ['ltn-depot-fluid-cleaning'] = function(ltn_settings, name) ltn_settings.depot_fluid_cleaning = setting_number(settings.global[name]) end,
    ['ltn-stop-default-network'] = function(ltn_settings, name) ltn_settings.default_network = setting_int(settings.global[name]) end,
    ['ltn-provider-show-existing-cargo'] = function(ltn_settings, name) ltn_settings.provider_show_existing_cargo = setting_bool(settings.global[name]) end,
    ['ltn-provider-ignore-stopped-train'] = function(ltn_settings, name) ltn_settings.requester_ignores_trains = setting_bool(settings.global[name]) end,

    ['ltn-schedule-fuel-station'] = function(ltn_settings, name) ltn_settings.enable_fuel_stations = setting_bool(settings.global[name]) end,
    ['ltn-fuel-station-interrupt'] = function(ltn_settings, name) ltn_settings.use_fuel_station_interrupt = setting_bool(settings.global[name]) end,
    ['ltn-schedule-reset-interrupts'] = function(ltn_settings, name) ltn_settings.reset_interrupts = setting_bool(settings.global[name]) end,
    ['ltn-schedule-reselect-depot'] = function(ltn_settings, name) ltn_settings.reselect_depot = setting_bool(settings.global[name]) end,
    ['ltn-advanced-cross-surface-delivery'] = function(ltn_settings, name) ltn_settings.advanced_cross_surface_delivery = setting_bool(settings.global[name]) end,
    ['ltn-depot-fudge-factor'] = function(ltn_settings, name) ltn_settings.depot_fudge_factor = setting_int(settings.global[name]) end,
    ['ltn-depot-stop-limit-trains'] = function(ltn_settings, name) ltn_settings.depot_limit_trains = setting_int(settings.startup[name]) end,
    ['ltn-limit-eligible-trains'] = function(ltn_settings, name) ltn_settings.limit_eligible_trains = setting_int(settings.global[name]) end,
}

---@type table<string, ltn.PlayerSettingFunction>
local change_player_settings = {
    ['ltn-interface-factorio-alerts'] = function(ltn_player_settings, name, player_index)
        ltn_player_settings.factorio_alerts = setting_bool(settings.get_player_settings(player_index)[name] or settings.player_default[name]) end,
    ['ltn-interface-console-messages'] = function(ltn_player_settings, name, player_index)
        ltn_player_settings.console_messages = setting_bool(settings.get_player_settings(player_index)[name] or settings.player_default[name]) end,
}

function LtnSettings:init()
    for name, setter in pairs(change_settings) do
        setter(self, name)
    end
end

---@param player_index integer
---@return ltn.PlayerSettings new_settings
function LtnSettings.init_player(player_index)
    local new_settings = {}
    for name, setter in pairs(change_player_settings) do
        setter(new_settings, name, player_index)
    end

    return new_settings
end

---@param player_index integer
---@return ltn.PlayerSettings player_settings
function LtnSettings.get_player_settings(player_index)
    player_settings[player_index] = player_settings[player_index] or LtnSettings.init_player(player_index)
    return player_settings[player_index]
end

---@param event EventData.on_runtime_mod_setting_changed
function LtnSettings.on_config_changed(event)
    local name = event.setting
    if event.setting_type == 'runtime-per-user' then
        if event.player_index and change_player_settings[name] then
            player_settings[event.player_index] = LtnSettings.get_player_settings(event.player_index)
            change_player_settings[name](player_settings[event.player_index], name, event.player_index)
        end
    else
        if change_settings[name] then
            local tick_update = change_settings[name](LtnSettings, name) or false
            if tick_update then
                tools.updateDispatchTicker()
            end
        end
    end
end

return LtnSettings
