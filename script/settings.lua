--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 * localizes and converts global runtime settings
 *
 * See LICENSE.md in the project directory for license information.
--]]

message_level                = tonumber(settings.global['ltn-interface-console-level'].value)
debug_log                    = settings.global['ltn-interface-debug-logfile'].value
message_include_gps          = settings.global['ltn-interface-message-gps'].value

delivery_timeout             = settings.global['ltn-dispatcher-delivery-timeout'].value * 60
depot_inactivity             = settings.global['ltn-dispatcher-depot-inactivity'].value * 60
dispatcher_enabled           = settings.global['ltn-dispatcher-enabled'].value
finish_loading               = settings.global['ltn-dispatcher-finish-loading'].value
dispatcher_nth_tick          = settings.global['ltn-dispatcher-nth_tick'].value
min_provided                 = settings.global['ltn-dispatcher-provider-threshold'].value
requester_delivery_reset     = settings.global['ltn-dispatcher-requester-delivery-reset'].value
min_requested                = settings.global['ltn-dispatcher-requester-threshold'].value
schedule_cc                  = settings.global['ltn-dispatcher-schedule-circuit-control'].value
stop_timeout                 = settings.global['ltn-dispatcher-stop-timeout'].value * 60
dispatcher_updates_per_tick  = settings.global['ltn-dispatcher-updates-per-tick'].value

depot_reset_filters          = settings.global['ltn-depot-reset-filters'].value
depot_fluid_cleaning         = settings.global['ltn-depot-fluid-cleaning'].value

default_network              = settings.global['ltn-stop-default-network'].value

provider_show_existing_cargo = settings.global['ltn-provider-show-existing-cargo'].value
requester_ignores_trains     = settings.global['ltn-provider-ignore-stopped-train'].value

condition_stop_timeout       = { type = 'time', compare_type = 'or', ticks = stop_timeout }

if dispatcher_nth_tick > 1 then
    dispatcher_updates_per_tick = 1
end

local change_settings = {
    ['ltn-interface-console-level'] = function() message_level = tonumber(settings.global['ltn-interface-console-level'].value) end,
    ['ltn-interface-message-gps'] = function() message_include_gps = settings.global['ltn-interface-message-gps'].value end,
    ['ltn-interface-debug-logfile'] = function() debug_log = settings.global['ltn-interface-debug-logfile'].value end,
    ['ltn-dispatcher-requester-threshold'] = function() min_requested = settings.global['ltn-dispatcher-requester-threshold'].value end,
    ['ltn-dispatcher-provider-threshold'] = function() min_provided = settings.global['ltn-dispatcher-provider-threshold'].value end,
    ['ltn-dispatcher-schedule-circuit-control'] = function() schedule_cc = settings.global['ltn-dispatcher-schedule-circuit-control'].value end,
    ['ltn-dispatcher-depot-inactivity'] = function() depot_inactivity = settings.global['ltn-dispatcher-depot-inactivity'].value * 60 end,
    ['ltn-dispatcher-stop-timeout'] = function()
        stop_timeout = settings.global['ltn-dispatcher-stop-timeout'].value * 60
        condition_stop_timeout = { type = 'time', compare_type = 'or', ticks = stop_timeout }
    end,
    ['ltn-dispatcher-delivery-timeout'] = function() delivery_timeout = settings.global['ltn-dispatcher-delivery-timeout'].value * 60 end,
    ['ltn-dispatcher-finish-loading'] = function() finish_loading = settings.global['ltn-dispatcher-finish-loading'].value end,
    ['ltn-dispatcher-requester-delivery-reset'] = function() requester_delivery_reset = settings.global['ltn-dispatcher-requester-delivery-reset'].value end,
    ['ltn-dispatcher-enabled'] = function() dispatcher_enabled = settings.global['ltn-dispatcher-enabled'].value end,
    ['ltn-dispatcher-updates-per-tick'] = function()
        if dispatcher_nth_tick == 1 then
            dispatcher_updates_per_tick = settings.global['ltn-dispatcher-updates-per-tick'].value
        else
            dispatcher_updates_per_tick = 1
        end
    end,
    ['ltn-dispatcher-nth_tick'] = function()
        if dispatcher_nth_tick == 1 then
            dispatcher_updates_per_tick = settings.global['ltn-dispatcher-updates-per-tick'].value
        else
            dispatcher_updates_per_tick = 1
        end
        script.on_nth_tick(nil)
        if next(storage.LogisticTrainStops) then
            script.on_nth_tick(dispatcher_nth_tick, OnTick)
        end
    end,
    ['ltn-depot-reset-filters'] = function() depot_reset_filters = settings.global['ltn-depot-reset-filters'].value end,
    ['ltn-depot-fluid-cleaning'] = function() depot_fluid_cleaning = settings.global['ltn-depot-fluid-cleaning'].value end,
    ['ltn-stop-default-network'] = function() default_network = settings.global['ltn-stop-default-network'].value end,
    ['ltn-provider-show-existing-cargo'] = function() provider_show_existing_cargo = settings.global['ltn-provider-show-existing-cargo'].value end,
    ['ltn-provider-ignore-stopped-train'] = function() requester_ignores_trains = settings.global['ltn-provider-ignore-stopped-train'].value end,
}


script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event and change_settings[event.setting] then
        change_settings[event.setting]()
    end
end)
