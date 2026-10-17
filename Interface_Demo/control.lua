--[[
  LTN API demo
  Copyright (c) 2019 Optera

  For complete listing of events and properties refer to https://forums.factorio.com/viewtopic.php?f=214&t=51072#p397844


  This is free and unencumbered software released into the public domain.

  Anyone is free to copy, modify, publish, use, compile, sell, or
  distribute this software, either in source code form or as a compiled
  binary, for any purpose, commercial or non-commercial, and by any
  means.

  In jurisdictions that recognize copyright laws, the author or authors
  of this software dedicate any and all copyright interest in the
  software to the public domain. We make this dedication for the benefit
  of the public at large and to the detriment of our heirs and
  successors. We intend this dedication to be an overt act of
  relinquishment in perpetuity of all present and future rights to this
  software under copyright law.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
  OTHER DEALINGS IN THE SOFTWARE.

  For more information, please refer to <http://unlicense.org/>
--]]

-- LTN interface event functions

---@class (partial) LuaRemote.InterfaceMap
---@field logistic-train-network ltn.RemoteInterface

---@class ltn.RemoteInterface
---@field on_stops_updated fun(): defines.events
---@field on_dispatcher_updated fun(): defines.events
---@field on_dispatcher_no_train_found fun(): defines.events
---@field on_delivery_created fun(): defines.events
---@field on_delivery_pickup_complete fun(): defines.events
---@field on_delivery_completed fun(): defines.events
---@field on_delivery_failed fun(): defines.events
---@field on_delivery_reassigned fun(): defines.events
---@field on_stops_updated_event fun(): defines.events
---@field on_provider_missing_cargo fun(): defines.events
---@field on_provider_unscheduled_cargo fun(): defines.events
---@field on_requester_unscheduled_cargo fun(): defines.events
---@field on_requester_remaining_cargo fun(): defines.events
---@field connect_surfaces fun(entity1: LuaEntity?, entity2: LuaEntity?, network_id: (integer|string)?)
---@field disconnect_surfaces fun(entity1: LuaEntity?, entity2: LuaEntity?)
---@field clear_all_surface_connections fun()
---@field reassign_delivery fun(old_train_id: uint32, new_train: LuaTrain): boolean
---@field get_or_create_next_temp_stop fun(train: LuaTrain, schedule_index: integer?)
---@field get_next_logistic_stop fun(train: LuaTrain, schedule_index: integer?) : integer?, integer?, ("provider"|"requester")?
---@field exclude_from_fuel_schedule fun(name: string?)

function OnStopsUpdated(event)
  log("Stop Data:"..serpent.block(event) )
end

function OnDispatcherUpdated(event)
  log("Dispatcher Data:"..serpent.block(event) )
end

---- Initialisation  ----
script.on_init(function()
  -- register events from LTN
  if remote.interfaces["logistic-train-network"] then
    script.on_event(remote.call("logistic-train-network", "on_stops_updated"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "on_dispatcher_updated"), OnDispatcherUpdated)
  end
end)

script.on_load(function(_data)
  -- register events from LTN
  if remote.interfaces["logistic-train-network"] then
    script.on_event(remote.call("logistic-train-network", "on_stops_updated"), OnStopsUpdated)
    script.on_event(remote.call("logistic-train-network", "on_dispatcher_updated"), OnDispatcherUpdated)
    --[[ alternative anonymous function:
         has to be copied between on_init and on_load
         script.on_event(remote.call("logistic-train-network", "on_stops_updated"), function(event)
           do something with event.data
         end)
     ]]
  end
end)
