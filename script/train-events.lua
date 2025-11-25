--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local tools = require('script.tools')
local schedule = require('script.schedule')

-- update stop output when train enters stop
---@param train LuaTrain
function TrainArrives(train)
    local dispatcher = tools.getDispatcher()
    local stopped_trains = tools.getStoppedTrains()

    local stopID = train.station.unit_number
    local stop = storage.LogisticTrainStops[stopID]
    if not stop then return end

    local stop_name = stop.entity.backer_name
    -- assign main loco name and force

    local loco = tools.getMainLocomotive(train)
    local trainForce = loco and loco.force
    local trainName = loco and loco.backer_name

    -- add train to stopped_trains
    stopped_trains[train.id] = {
        train = train,
        name = trainName,
        force = trainForce,
        stopID = stopID,
    }

    -- add train to storage.LogisticTrainStops
    stop.parked_train = train
    stop.parked_train_id = train.id

    local frontDistance = tools.getDistance(train.front_stock.position, train.station.position)
    local backDistance = tools.getDistance(train.back_stock.position, train.station.position)
    if frontDistance > backDistance then
        stop.parked_train_faces_stop = false
    else
        stop.parked_train_faces_stop = true
    end
    local is_provider = false

    -- if message_level >= 3 then tools.printmsg({"ltn-message.train-arrived", tostring(trainName), stop_name}, trainForce, false) end
    if message_level >= 3 then tools.printmsg({ 'ltn-message.train-arrived', tools.richTextForTrain(train), string.format('[train-stop=%d]', stopID) }, trainForce) end
    if debug_log then tools.log(5, 'TrainArrives', 'Train [%d] \"%s\": arrived at LTN-stop [%d] \"%s\"; train_faces_stop: %s', train.id, trainName, stopID, stop_name, stop.parked_train_faces_stop) end

    if stop.error_code == 0 then
        local stop_type = GetStationType(stop)

        if stop_type == station_type.depot then
            -- ----------------------------------------------------------------------------------------
            -- Depot Operations
            -- ----------------------------------------------------------------------------------------

            local delivery = dispatcher.Deliveries[train.id]
            if delivery then
                -- delivery should have been removed when leaving requester. Handle like delivery timeout.
                local from_entity = storage.LogisticTrainStops[delivery.from_id] and storage.LogisticTrainStops[delivery.from_id].entity
                local to_entity = storage.LogisticTrainStops[delivery.to_id] and storage.LogisticTrainStops[delivery.to_id].entity

                if message_level >= 1 then tools.printmsg({ 'ltn-message.delivery-removed-depot', tools.richTextForStop(from_entity) or delivery.from, tools.richTextForStop(to_entity) or delivery.to }, delivery.force) end
                if debug_log then tools.log(5, 'TrainArrives', 'Train [%d] \"%s\": Entered Depot with active Delivery. Failing Delivery and reseting train.', train.id, trainName) end

                ---@type ltn.EventData.on_delivery_failed
                local data = {
                    train_id = train.id,
                    shipment = delivery.shipment
                }
                script.raise_event(on_delivery_failed_event, data)

                RemoveDelivery(train.id)
            end

            -- clean fluid residue
            local train_items = train.get_contents()
            local train_fluids = train.get_fluid_contents()
            if table_size(train_fluids) > 0 then
                if LtnSettings.depot_fluid_cleaning > 0 then
                    for fluid, count in pairs(train_fluids) do
                        local cleaning_amount = math.ceil(math.min(count, LtnSettings.depot_fluid_cleaning))
                        local removed = math.ceil(train.remove_fluid { name = fluid, amount = cleaning_amount })
                        if debug_log then tools.log(5, 'TrainArrives', 'Train \"%s\": Depot fluid removal %s %f/%f', trainName, fluid, removed, count) end
                    end
                elseif LtnSettings.depot_fluid_cleaning < 0 then
                    train.clear_fluids_inside()
                end
                train_fluids = train.get_fluid_contents()
            end

            -- check for leftover cargo
            if table_size(train_items) > 0 then
                create_alert(stop.entity, 'cargo-warning', { 'ltn-message.depot_left_over_cargo', trainName, stop_name }, trainForce)
            end
            if table_size(train_fluids) > 0 then
                create_alert(stop.entity, 'cargo-warning', { 'ltn-message.depot_left_over_cargo', trainName, stop_name }, trainForce)
            end

            tools.increaseAvailableCapacity(train, stop)

            -- reset schedule
            schedule:resetInterrupts(train)
            schedule:resetSchedule(train, stop, true)
            schedule:updateRefuelSchedule(train, stop.network_id)

            -- reset filters and bars
            if LtnSettings.depot_reset_filters and train.cargo_wagons then
                for _, wagon in pairs(train.cargo_wagons) do
                    local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
                    if inventory then
                        if inventory.is_filtered() then
                            -- log("Cargo-Wagon["..tostring(n).."]: resetting "..tostring(#inventory).." filtered slots.")
                            for slotIndex = 1, #inventory, 1 do
                                inventory.set_filter(slotIndex, nil)
                            end
                        end
                        if inventory.supports_bar and #inventory - inventory.get_bar() > 0 then
                            -- log("Cargo-Wagon["..tostring(n).."]: resetting "..tostring(#inventory - inventory.get_bar()).." locked slots.")
                            inventory.set_bar()
                        end
                    end
                end
            end

            setLamp(stop, 'blue', 1)
        elseif stop_type == station_type.station then
            -- ----------------------------------------------------------------------------------------
            -- Provider / Requester operations
            -- ----------------------------------------------------------------------------------------

            -- check requester for incorrect shipment
            local delivery = dispatcher.Deliveries[train.id]
            if delivery then
                is_provider = delivery.from_id == stop.entity.unit_number
                if delivery.to_id == stop.entity.unit_number then
                    local requester_unscheduled_cargo = false

                    ---@type ltn.Shipment
                    local unscheduled_load = {}

                    for _, cargo in pairs(train.get_contents()) do
                        local item = tools.createItemIdentifierFromItemWithQualityCount(cargo)
                        if not delivery.shipment[item] then
                            requester_unscheduled_cargo = true
                            unscheduled_load[item] = cargo.count
                        end
                    end

                    for name, cargo in pairs(train.get_fluid_contents()) do
                        local item = tools.createItemIdentifierFluidName(name)
                        if not delivery.shipment[item] then
                            requester_unscheduled_cargo = true
                            unscheduled_load[item] = math.ceil(cargo)
                        end
                    end

                    if requester_unscheduled_cargo then
                        create_alert(stop.entity, 'cargo-alert', { 'ltn-message.requester_unscheduled_cargo', trainName, stop_name }, trainForce)

                        ---@type ltn.EventData.unscheduled_cargo
                        local data = {
                            train = train,
                            station = stop.entity,
                            planned_shipment = delivery.shipment,
                            unscheduled_load = unscheduled_load
                        }
                        script.raise_event(on_requester_unscheduled_cargo_alert, data)
                    end
                end

                -- only check dynamic refueling if a delivery exists (which contains the network id)
                if LtnSettings.enable_fuel_stations and not LtnSettings.use_fuel_station_interrupt then
                    local fuel_station = schedule:selectFuelStation(train, delivery.network_id)
                    if fuel_station then
                        schedule:scheduleDynamicRefueling(train, fuel_station)
                    end
                end
            end


            -- set lamp to blue for LTN controlled trains
            for i = 1, #stop.active_deliveries, 1 do
                if stop.active_deliveries[i] == train.id then
                    setLamp(stop, 'blue', #stop.active_deliveries)
                    break
                end
            end
        elseif stop_type == station_type.fuel_stop then
            -- ----------------------------------------------------------------------------------------
            -- Refuel operations
            -- ----------------------------------------------------------------------------------------

            setLamp(stop, 'blue', 1)
        end
    end

    UpdateStopOutput(stop, is_provider and not LtnSettings.provider_show_existing_cargo)
end

--- update stop output when train leaves stop
--- when called from on_train_created stoppedTrain.train will be invalid
---@param trainID number
function TrainLeaves(trainID)
    local dispatcher = tools.getDispatcher()
    local stopped_trains = tools.getStoppedTrains()

    local leavingTrain = stopped_trains[trainID] -- checked before every call of TrainLeaves
    assert(leavingTrain)                         -- TODO: test this!

    local train = leavingTrain.train
    local stopID = leavingTrain.stopID
    local stop = storage.LogisticTrainStops[stopID]
    if not stop then
        if debug_log then tools.log(5, 'TrainLeaves', 'Error: StopID [%d] not found in storage.LogisticTrainStops', stopID) end

        stopped_trains[trainID] = nil
        return
    end

    if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
        if debug_log then tools.log(5, 'TrainLeaves', 'Error: StopID [%d] contains invalid entity. Processing skipped, train inventory not updated.', stopID) end

        stopped_trains[trainID] = nil
        -- don't call RemoveStop here as RemoveStop calls TrainLeaves again
        return
    end

    local stop_name = stop.entity.backer_name

    local stop_type = GetStationType(stop)

    if stop_type == station_type.depot then
        -- ----------------------------------------------------------------------------------------
        -- Depot operations
        -- ----------------------------------------------------------------------------------------

        tools.reduceAvailableCapacity(trainID)

        if stop.error_code == 0 then
            setLamp(stop, 'green', 1)
        end

        if debug_log then tools.log(5, 'TrainLeaves', 'Train [%d] \"%s\": left Depot [%d] \"%s\".', trainID, leavingTrain.name, stopID, stop.entity.backer_name) end
    elseif stop_type == station_type.station then
        -- ----------------------------------------------------------------------------------------
        -- Provider / Requester operations
        -- ----------------------------------------------------------------------------------------

        -- remove delivery from stop
        for i = #stop.active_deliveries, 1, -1 do
            if stop.active_deliveries[i] == trainID then
                table.remove(stop.active_deliveries, i)
            end
        end

        local delivery = dispatcher.Deliveries[trainID]
        if train.valid and delivery then
            if delivery.from_id == stop.entity.unit_number then
                -- update delivery counts to train inventory
                local actual_load = {}
                local unscheduled_load = {}
                local provider_unscheduled_cargo = false
                local provider_missing_cargo = false

                for _, cargo in pairs(train.get_contents()) do
                    local item = tools.createItemIdentifierFromItemWithQualityCount(cargo)
                    local planned_count = delivery.shipment[item]
                    if planned_count then
                        actual_load[item] = cargo.count -- update shipment to actual inventory
                        if cargo.count < planned_count then
                            -- underloaded
                            provider_missing_cargo = true
                        end
                    else
                        -- loaded wrong items
                        provider_unscheduled_cargo = true
                        unscheduled_load[item] = cargo.count
                    end
                end

                for name, cargo in pairs(train.get_fluid_contents()) do
                    local item = tools.createItemIdentifierFluidName(name)
                    local planned_count = delivery.shipment[item]
                    if planned_count then
                        actual_load[item] = math.ceil(cargo) -- update shipment actual inventory
                        if planned_count - cargo > 0.1 then  -- prevent rounding errors
                            -- underloaded
                            provider_missing_cargo = true
                        end
                    else
                        -- loaded wrong fluids
                        provider_unscheduled_cargo = true
                        unscheduled_load[item] = cargo
                    end
                end

                delivery.pickupDone = true -- remove reservations from this delivery

                if debug_log then tools.log(5, 'TrainLeaves', 'Train [%d] \"%s\": left Provider [%d] \"%s\"; cargo: %s; unscheduled: %s ', trainID, leavingTrain.name, stopID, stop.entity.backer_name, serpent.line(actual_load), serpent.line(unscheduled_load)) end

                stopped_trains[trainID] = nil

                if provider_missing_cargo then
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.provider_missing_cargo', leavingTrain.name, stop_name }, leavingTrain.force)

                    ---@type ltn.EventData.provider_missing_cargo
                    local data = {
                        train = train,
                        station = stop.entity,
                        planned_shipment = delivery.shipment,
                        actual_shipment = actual_load
                    }

                    script.raise_event(on_provider_missing_cargo_alert, data)
                end

                if provider_unscheduled_cargo then
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.provider_unscheduled_cargo', leavingTrain.name, stop_name }, leavingTrain.force)

                    ---@type ltn.EventData.unscheduled_cargo
                    local data = {
                        train = train,
                        station = stop.entity,
                        planned_shipment = delivery.shipment,
                        unscheduled_load = unscheduled_load
                    }
                    script.raise_event(on_provider_unscheduled_cargo_alert, data)
                end

                ---@type ltn.EventData.delivery_pickup_complete
                local data = {
                    train_id = trainID,
                    train = train,
                    planned_shipment = delivery.shipment,
                    actual_shipment = actual_load
                }
                script.raise_event(on_delivery_pickup_complete_event, data)

                delivery.shipment = actual_load
            elseif delivery.to_id == stop.entity.unit_number then
                -- reset schedule before API events
                if LtnSettings.requester_delivery_reset then
                    local depot = schedule:selectDepot(leavingTrain.train, delivery.network_id)
                    schedule:resetSchedule(train, depot, true)
                end

                local remaining_load = {}
                local requester_left_over_cargo = false

                for _, cargo in pairs(train.get_contents()) do
                    -- not fully unloaded
                    local item = tools.createItemIdentifierFromItemWithQualityCount(cargo)
                    requester_left_over_cargo = true
                    remaining_load[item] = cargo.count
                end

                for name, cargo in pairs(train.get_fluid_contents()) do
                    -- not fully unloaded
                    local item = tools.createItemIdentifierFluidName(name)
                    requester_left_over_cargo = true
                    remaining_load[item] = cargo
                end

                if debug_log then tools.log(5, 'TrainLeaves', 'Train [%d] \"%s\": left Requester [%d] \"%s\" with left over cargo: %s', trainID, leavingTrain.name, stopID, stop.entity.backer_name, serpent.line(remaining_load)) end

                -- signal completed delivery and remove it
                if requester_left_over_cargo then
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.requester_left_over_cargo', leavingTrain.name, stop_name }, leavingTrain.force)

                    ---@type ltn.EventData.requester_remaining_cargo
                    local data = {
                        train = train,
                        station = stop.entity,
                        remaining_load = remaining_load
                    }
                    script.raise_event(on_requester_remaining_cargo_alert, data)
                end

                ---@type ltn.EventData.delivery_complete
                local data = {
                    train_id = trainID,
                    train = train,
                    shipment = delivery.shipment
                }
                script.raise_event(on_delivery_completed_event, data)

                RemoveDelivery(trainID)
            else
                if debug_log then tools.log(5, 'TrainLeaves', 'Train [%d] \"%s\": left LTN-stop [%d] \"%s\".', trainID, leavingTrain.name, stopID, stop.entity.backer_name) end
            end
        end
        if stop.error_code == 0 then
            if #stop.active_deliveries > 0 then
                setLamp(stop, 'yellow', #stop.active_deliveries)
            else
                setLamp(stop, 'green', 1)
            end
        end
    elseif stop_type == station_type.fuel_stop then
        -- ----------------------------------------------------------------------------------------
        -- Fuel station operations
        -- ----------------------------------------------------------------------------------------

        setLamp(stop, 'cyan', 1)

        -- temporarily remove the fuel stop, it gets readded at the depot
        -- otherwise the train could end up in an endless refueling loop
        schedule:removeFuelInterrupt(train)
    end

    -- remove train reference
    stop.parked_train = nil
    stop.parked_train_id = nil
    -- if message_level >= 3 then tools.printmsg({"ltn-message.train-left", tostring(leavingTrain.name), stop.entity.backer_name}, leavingTrain.force) end
    if message_level >= 3 then tools.printmsg({ 'ltn-message.train-left', tools.richTextForTrain(train, leavingTrain.name), string.format('[train-stop=%d]', stopID) }, leavingTrain.force) end

    UpdateStopOutput(stop)

    stopped_trains[trainID] = nil
end

function OnTrainStateChanged(event)
    local stopped_trains = tools.getStoppedTrains()

    -- log(game.tick.." (OnTrainStateChanged) Train name: "..tostring(tools.getTrainName(event.train))..", train.id:"..tostring(event.train.id).." stop: "..tostring(event.train.station and event.train.station.backer_name)..", state: "..reverse_defines.train_state[event.old_state].." > "..reverse_defines.train_state[event.train.state] )
    local train = event.train
    if train.state == defines.train_state.wait_station and train.station ~= nil and ltn_stop_entity_names[train.station.name] then
        TrainArrives(train)
    elseif event.old_state == defines.train_state.wait_station and stopped_trains[train.id] then
        TrainLeaves(train.id)
    end
end

--- updates or removes delivery references
---@param old_train_id number
---@param new_train LuaTrain
---@return ltn.Delivery? The moved delivery, if any.
function Update_Delivery(old_train_id, new_train)
    local dispatcher = tools.getDispatcher()
    local stopped_trains = tools.getStoppedTrains()

    local delivery = dispatcher.Deliveries[old_train_id]

    -- expanded RemoveDelivery(old_train_id) to also update
    for stopID, stop in pairs(storage.LogisticTrainStops) do
        if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
            RemoveStop(stopID)
        else
            for i = #stop.active_deliveries, 1, -1 do --trainID should be unique => checking matching stop name not required
                if stop.active_deliveries[i] == old_train_id then
                    if delivery then
                        stop.active_deliveries[i] = new_train.id -- update train id if delivery exists
                    else
                        table.remove(stop.active_deliveries, i)  -- otherwise remove entry
                        if #stop.active_deliveries > 0 then
                            setLamp(stop, 'yellow', #stop.active_deliveries)
                        else
                            setLamp(stop, 'green', 1)
                        end
                    end
                end
            end
        end
    end

    -- copy dispatcher.Deliveries[old_train_id] to new_train.id and change attached train in delivery
    if delivery then
        delivery.train = new_train
        dispatcher.Deliveries[new_train.id] = delivery
    end

    if stopped_trains[old_train_id] then
        TrainLeaves(old_train_id) -- removal only, new train is added when on_train_state_changed fires with wait_station afterwards
    end

    dispatcher.Deliveries[old_train_id] = nil

    tools.reassignTrainRecord(old_train_id, new_train)

    if delivery then
        ---@type ltn.EventData.on_delivery_reassigned
        local data = {
            old_train_id = old_train_id,
            new_train_id = new_train.id,
            shipment = delivery.shipment
        }
        script.raise_event(on_delivery_reassigned_event, data)
    end

    return delivery
end

---@param event EventData.on_train_created
function OnTrainCreated(event)
    -- log("(on_train_created) Train name: "..tostring(tools.getTrainName(event.train))..", train.id:"..tostring(event.train.id)..", .old_train_id_1:"..tostring(event.old_train_id_1)..", .old_train_id_2:"..tostring(event.old_train_id_2)..", state: "..tostring(event.train.state))
    -- on_train_created always sets train.state to 9 manual, scripts have to set the train back to its former state.

    if event.old_train_id_1 then Update_Delivery(event.old_train_id_1, event.train) end
    if event.old_train_id_2 then Update_Delivery(event.old_train_id_2, event.train) end
end
