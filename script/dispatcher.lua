--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local util = require('util')

local tools = require('script.tools')

local request_processor = require('script.request_processor')

-- amount of time a "knownTrain" record is retained even though the
-- train has gone away. This allows reassigning information e.g. when
-- traveling through a space elevator even though the train was destroyed
local DEAD_TRAIN_LINGER_TIME = 240

-- update dispatcher Deliveries.force when forces are removed/merged
script.on_event(defines.events.on_forces_merging, function(event)
    local dispatcher = tools.getDispatcher()

    for _, delivery in pairs(dispatcher.Deliveries) do
        if delivery.force == event.source then
            delivery.force = event.destination
        end
    end
end)

---@param id integer
function DispatcherOnObjectDestroyed(id)
    local dispatcher = tools.getDispatcher()

    -- the destroyed object may have been a surface connection object.
    -- This is expensive but the objects should not be deleted that often
    -- if you build a mod that creates and deletes surface connections, please
    -- remove them before destroying the objects
    for _, delivery in pairs(dispatcher.Deliveries) do
        for idx, surface_connection in pairs(delivery.surface_connections) do
            if not ((surface_connection.entity1 and surface_connection.entity1.valid) and
                    (surface_connection.entity2 and surface_connection.entity2.valid)) then
                delivery.surface_connections[idx] = nil
            end
        end
    end
end

---------------------------------- MAIN LOOP STAGES ----------------------------------

---@param event EventData.on_tick
---@return ltn.TickState?
local function DispatcherReset(event)
    local dispatcher = tools.getDispatcher()

    -- update stops
    storage.tick_stop_index = nil

    -- update deliveries
    storage.tick_request_index = nil

    storage.tick_interval_start = event.tick

    -- clear Dispatcher.Storage
    dispatcher.Provided = {}
    dispatcher.Requests = {}
    dispatcher.Provided_by_Stop = {}
    dispatcher.Requests_by_Stop = {}
    dispatcher.Pending_Requests = {}
    dispatcher.new_Deliveries = {}

    return nil
end

----------------------------------------------------------------------------------------

---@param event EventData.on_tick
---@return ltn.TickState?
local function DispatcherUpdateStops(event)
    ---@type integer?
    local stopID = storage.tick_stop_index

    if stopID and not storage.LogisticTrainStops[stopID] then
        tools.printmsg(2, function()
            return { 'ltn-message.error-invalid-stop-index', storage.tick_stop_index }
        end)

        tools.log(6, 'OnTick', 'Invalid storage.tick_stop_index %d in storage.LogisticTrainStops. Removing stop and starting over.', function()
            return storage.tick_stop_index
        end)

        RemoveStop(stopID)
        return ltn_tick_state.reset
    end

    local stop_count = LtnSettings:getStopUpdatesPerTick()

    if stop_count > 0 then
        ---@type ltn.TrainStop
        local stop
        repeat
            stopID, stop = next(storage.LogisticTrainStops, storage.tick_stop_index)
            if stopID then
                tools.log(6, 'OnTick', '%d updating stopID %d', function()
                    return event.tick, stopID
                end)
                UpdateStop(stopID, stop)
            end
            stop_count = stop_count - 1
            storage.tick_stop_index = stopID
        until stop_count == 0 or not stopID
    end

    -- if there are more stops, stay in the current state, otherwise switch to next state
    return stopID and ltn_tick_state.update_stops or nil
end

----------------------------------------------------------------------------------------

---@param event EventData.on_tick
---@return ltn.TickState?
local function DispatcherUpdateDeliveries(event)
    local dispatcher = tools.getDispatcher()

    -- clean up deliveries in case train was destroyed or removed
    local activeDeliveryTrains = ''

    for trainID, delivery in pairs(dispatcher.Deliveries) do
        if not (delivery.train and delivery.train.valid) then
            local from_entity = storage.LogisticTrainStops[delivery.from_id] and storage.LogisticTrainStops[delivery.from_id].entity
            local to_entity = storage.LogisticTrainStops[delivery.to_id] and storage.LogisticTrainStops[delivery.to_id].entity

            tools.printmsg(1, function()
                return { 'ltn-message.delivery-removed-train-invalid', tools.richTextForStop(from_entity) or delivery.from, tools.richTextForStop(to_entity) or delivery.to }
            end, delivery.force)

            tools.log(6, 'OnTick', 'Delivery from %s to %s removed. Train no longer valid.', function()
                return delivery.from, delivery.to
            end)

            ---@type ltn.EventData.on_delivery_failed
            local data = {
                train_id = trainID,
                shipment = delivery.shipment
            }
            script.raise_event(on_delivery_failed_event, data)

            RemoveDelivery(trainID)
        elseif event.tick - delivery.started > LtnSettings.delivery_timeout then
            local from_entity = storage.LogisticTrainStops[delivery.from_id] and storage.LogisticTrainStops[delivery.from_id].entity
            local to_entity = storage.LogisticTrainStops[delivery.to_id] and storage.LogisticTrainStops[delivery.to_id].entity

            tools.printmsg(1, function()
                return { 'ltn-message.delivery-removed-timeout', tools.richTextForStop(from_entity) or delivery.from, tools.richTextForStop(to_entity) or delivery.to, event.tick - delivery.started }
            end, delivery.force)

            tools.log(6, 'OnTick', 'Delivery from %s to %s removed. Timed out after %d/%d ticks.', function()
                return delivery.from, delivery.to, event.tick - delivery.started, LtnSettings.delivery_timeout
            end)

            ---@type ltn.EventData.on_delivery_failed
            local data = {
                train_id = trainID,
                shipment = delivery.shipment
            }
            script.raise_event(on_delivery_failed_event, data)

            RemoveDelivery(trainID)
        else
            activeDeliveryTrains = activeDeliveryTrains .. ' ' .. trainID
        end
    end

    tools.log(6, 'OnTick', 'Trains on deliveries: %s', function()
        return activeDeliveryTrains
    end)

    -- remove no longer active requests from dispatcher RequestAge[stopID]
    local newRequestAge = {}
    for _, request in pairs(dispatcher.Requests) do
        local ageIndex = request.item .. ',' .. request.stopID
        local age = dispatcher.RequestAge[ageIndex]
        if age then
            newRequestAge[ageIndex] = age
        end
    end
    dispatcher.RequestAge = newRequestAge

    -- sort requests by priority and age
    table.sort(dispatcher.Requests, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        else
            return a.age < b.age
        end
    end)

    return nil
end

----------------------------------------------------------------------------------------

---@param event EventData.on_tick
---@return ltn.TickState?
local function DispatcherDispatchTrains(event)
    local dispatcher = tools.getDispatcher()

    ---@type integer?
    local request_index = storage.tick_request_index

    if LtnSettings.dispatcher_enabled then
        tools.log(6, 'OnTick', 'Available train capacity: %d item stacks, %d fluid capacity.', function()
            return dispatcher.availableTrains_total_capacity, dispatcher.availableTrains_total_fluid_capacity
        end)

        -- snapshot Requests_by_Stop before any ProcessRequest calls mutate it
        if not request_index then
            dispatcher.Pending_Requests = util.copy(dispatcher.Requests_by_Stop)
        end

        -- reset on invalid index
        if request_index and not dispatcher.Requests[request_index] then
            tools.printmsg(1, function()
                return { 'ltn-message.error-invalid-request-index', storage.tick_request_index }
            end)

            tools.log(6, 'OnTick', 'Invalid storage.tick_request_index %s in dispatcher Requests. Starting over.', function()
                return tostring(storage.tick_request_index)
            end)

            return ltn_tick_state.reset
        end

        local request_count = LtnSettings:getRequestUpdatesPerTick()

        if request_count > 0 then
            ---@type ltn.Request
            local request
            repeat
                request_index, request = next(dispatcher.Requests, request_index)
                if request_index and request then
                    tools.log(6, 'OnTick', '%d parsing request %d/%d', function()
                        return event.tick, request_index, #dispatcher.Requests
                    end)
                    request_processor:processRequest(request_index, request)
                end
                request_count = request_count - 1
                storage.tick_request_index = request_index
            until request_count == 0 or not request_index
        end
    else
        tools.printmsg(1, function()
            return { 'ltn-message.warning-dispatcher-disabled' }
        end)

        tools.log(6, 'OnTick', 'Dispatcher disabled.')

        storage.tick_request_index = nil
    end

    -- if there are more requests, stay in the current state, otherwise switch to next state
    return request_index and ltn_tick_state.dispatch_trains or nil
end

----------------------------------------------------------------------------------------

--- raise events for mod API
---@param event EventData.on_tick
---@return ltn.TickState?
local function DispatcherApiEvents(event)
    local dispatcher = tools.getDispatcher()

    ---@type ltn.EventData.on_stops_updated
    local stops_data = {
        logistic_train_stops = storage.LogisticTrainStops,
    }
    script.raise_event(on_stops_updated_event, stops_data)

    ---@type ltn.EventData.on_dispatcher_updated
    local dispatcher_data = {
        update_interval = event.tick - storage.tick_interval_start,
        provided_by_stop = dispatcher.Provided_by_Stop,
        requests_by_stop = dispatcher.Pending_Requests,
        new_deliveries = dispatcher.new_Deliveries,
        deliveries = dispatcher.Deliveries,
        available_trains = dispatcher.availableTrains,
    }
    script.raise_event(on_dispatcher_updated_event, dispatcher_data)

    return nil
end

----------------------------------------------------------------------------------------

---@return ltn.TickState?
local function DispatcherCleanup()
    local dispatcher = tools.getDispatcher()

    for index, knownTrain in pairs(dispatcher.knownTrains) do
        if knownTrain.invalid_tick then
            if knownTrain.invalid_tick < game.tick then
                dispatcher.knownTrains[index] = nil
            end
        elseif not (knownTrain.train and knownTrain.train.valid) then
            knownTrain.invalid_tick = game.tick + DEAD_TRAIN_LINGER_TIME
        end
    end

    return nil
end

---------------------------------- MAIN LOOP ----------------------------------

--- @type table<ltn.TickState, fun(event: EventData.on_tick): ltn.TickState?>
local dispatcher_stages = {
    [ltn_tick_state.reset] = DispatcherReset,
    [ltn_tick_state.update_stops] = DispatcherUpdateStops,
    [ltn_tick_state.update_deliveries] = DispatcherUpdateDeliveries,
    [ltn_tick_state.dispatch_trains] = DispatcherDispatchTrains,
    [ltn_tick_state.api_events] = DispatcherApiEvents,
    [ltn_tick_state.cleanup] = DispatcherCleanup,
}

---@param event EventData.on_tick
function OnTick(event)
    tools.log(9, 'OnTick', 'Tick: %d, storage.tick_state: %s, storage.tick_stop_index: %s, storage.tick_request_index: %s', function()
        return event.tick, tostring(storage.tick_state), tostring(storage.tick_stop_index), tostring(storage.tick_request_index)
    end)

    local current_tick_state = storage.tick_state or ltn_tick_state.reset

    storage.tick_state = assert(dispatcher_stages[current_tick_state])(event) or storage.tick_state + 1
    if dispatcher_stages[storage.tick_state] then return end

    -- no next stage, go back to reset
    storage.tick_state = ltn_tick_state.reset
end

---------------------------------- DISPATCHER FUNCTIONS ----------------------------------

-- ensures removal of trainID from dispatcher Deliveries and stop.active_deliveries

---@param trainID number
function RemoveDelivery(trainID)
    local dispatcher = tools.getDispatcher()

    for stopID, stop in pairs(storage.LogisticTrainStops) do
        if not tools.isStopConsistent(stop) then
            RemoveStop(stopID)
        else
            for i = #stop.active_deliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
                if stop.active_deliveries[i] == trainID then
                    table.remove(stop.active_deliveries, i)
                    if #stop.active_deliveries > 0 then
                        setLamp(stop, 'yellow', #stop.active_deliveries)
                    else
                        setLamp(stop, 'green', 1)
                    end
                end
            end
        end
    end
    dispatcher.Deliveries[trainID] = nil
end
