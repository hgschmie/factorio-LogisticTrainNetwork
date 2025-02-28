--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local tools = require('script.tools')

local schedule = require('script.schedule')


---Finds the next logistic stop in the schedule of the given train. Returns nil if the train is not executing a delivery or has no further logistic stops in its schedule.
---@param train LuaTrain
---@param schedule_index integer? the index in the schedule to search from, `schedule.current` if omitted. Starts from the next position if the train is currently stopping at that station.
---@return integer? schedule_index the index of next logistic stop in the schedule or nil
---@return integer? id the unit_number of the logistic stop
---@return "provider"|"requester"|nil type
function GetNextLogisticStop(train, schedule_index)
    local dispatcher = tools.getDispatcher()

    if not (train and train.valid) then
        if debug_log then log('(GetNextLogisticStop) train not valid') end
        return
    end

    if not schedule:hasSchedule(train) then
        if debug_log then log(string.format('(GetNextLogisticStop) train [%d] has no schedule.', train.id)) end
        return
    end

    local delivery = dispatcher.Deliveries[train.id]
    if not delivery then
        if debug_log then log(string.format('(GetNextLogisticStop) train [%d] not found in deliveries.', train.id)) end
        return
    end

    local item = next(delivery.shipment)
    if not item then
        -- this can happen when the train was unable to load anything at the provider
        if debug_log then log(string.format('(GetNextLogisticStop) train [%d] no longer has a shipment list.', train.id)) end
        return
    end

    -- Comparing stop names is not enough to find the provider and the requester,
    -- they might share names with each other or another stop in the schedule.
    -- So use a heuristic that also looks at the wait conditions
    local identifier = tools.parseItemIdentifier(item)
    if not identifier then return end

    local records, current = schedule:getSchedule(train)

    local record_index = schedule_index or train.schedule.current or 2 -- defaulting to 1 is pointless because that's the depot
    if record_index == current and train.state == defines.train_state.wait_station then
        record_index = record_index + 1
    end

    local record = records[record_index]
    while record do
        local results = schedule:analyzeRecord(record.wait_conditions)
        local result = results[identifier]
        if result then
            if record.station == delivery.from and result.provider then
                return record_index, delivery.from_id, 'provider'
            end
            if record.station == delivery.to and result.requester then
                return record_index, delivery.to_id, 'requester'
            end
        end
        record_index = record_index + 1
        record = records[record_index]
    end
end

local temp_wait_condition = { { type = 'time', compare_type = 'and', ticks = 0 } }

---Ensures the next logistic stop in the schedule has a temporary stop if is on the same surface as the train.
---@param train LuaTrain
---@param schedule_index integer? the index in the schedule to search from, `schedule.current` if omitted. Starts from the next index if the train is currently stopping at that station.
---@return integer? stop_position index of created or existing temporary stop for next found logistic stop that was handled, nil if there is no further logistic stop or the next logistic stop is not on the same surface.
function GetOrCreateNextTempStop(train, schedule_index)
    local stop_schedule_index, stop_id = GetNextLogisticStop(train, schedule_index)
    if not stop_schedule_index then return end

    --unlike ProcessDelivery we need to consider that the stop entity might be gone
    local stop = storage.LogisticTrainStops[stop_id]
    if not stop or not stop.entity.valid then
        if debug_log then log(string.format('(UpdateSchedule) skipping stop [%d] for train [%d], stop-entity not valid', stop_id, train.id)) end
        return
    end

    local rail = stop.entity.connected_rail
    local rail_direction = stop.entity.connected_rail_direction
    if not rail or not rail_direction then
        if debug_log then log(string.format('(UpdateSchedule) skipping stop [%d] for train [%d], not connected to a rail', stop_id, train.id)) end
        return
    end

    -- the engine does not allow temp_stops on different surfaces
    -- locomotive might not work here, a new train on another surface could still be incomplete
    if train.carriages[1].surface ~= stop.entity.surface then
        if debug_log then log(string.format('(UpdateSchedule) stop [%d] is on a different surface than train [%d]', stop_id, train.id)) end
        return
    end

    -- insert temp stop in schedule
    local train_schedule = schedule:getSchedule(train)
    assert(train_schedule)
    local previous_record = train_schedule[stop_schedule_index - 1]
    if previous_record and previous_record.temporary then return stop_schedule_index - 1 end -- schedule already up-to-date for stop_position

    if debug_log then log(string.format('(UpdateSchedule) adding new temp-stop before stop [%d] at rail [%d] to train [%d] ', stop_id, rail.unit_number, train.id)) end

    schedule:temporaryStop(train, rail, rail_direction, stop_schedule_index)

    return stop_schedule_index
end

---reassigns an existing delivery from one train to another
---@param old_train_id integer
---@param new_train LuaTrain
---@return boolean reassigned true if the old train was executing a delivery, false otherwise
function ReassignDelivery(old_train_id, new_train)
    local dispatcher = tools.getDispatcher()

    -- check if delivery exists for given train id
    if not (old_train_id and dispatcher.Deliveries[old_train_id]) then
        if debug_log then log(string.format('(ReassignDelivery) train [%d] not found in deliveries.', old_train_id)) end
        return false
    end
    -- check if new train is valid
    if not (new_train and new_train.valid and new_train.object_name == 'LuaTrain') then
        if debug_log then log('(ReassignDelivery) Received new_train was invalid.') end
        return false
    end

    local delivery = Update_Delivery(old_train_id, new_train)
    return delivery and true or false
end
