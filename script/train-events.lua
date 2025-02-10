--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local Get_Distance = require('__flib__.position').distance
local Get_Main_Locomotive = require('__flib__.train').get_main_locomotive

-- update stop output when train enters stop
---@param train LuaTrain
function TrainArrives(train)
    local stopID = train.station.unit_number
    local stop = storage.LogisticTrainStops[stopID]
    if stop then
        local stop_name = stop.entity.backer_name
        -- assign main loco name and force
        local loco = Get_Main_Locomotive(train)
        local trainForce = nil
        local trainName = nil
        if loco then
            trainName = loco.backer_name
            trainForce = loco.force
        end

        -- add train to storage.StoppedTrains
        storage.StoppedTrains[train.id] = {
            train = train,
            name = trainName,
            force = trainForce,
            stopID = stopID,
        }

        -- add train to storage.LogisticTrainStops
        stop.parked_train = train
        stop.parked_train_id = train.id

        local frontDistance = Get_Distance(train.front_stock.position, train.station.position)
        local backDistance = Get_Distance(train.back_stock.position, train.station.position)
        if frontDistance > backDistance then
            stop.parked_train_faces_stop = false
        else
            stop.parked_train_faces_stop = true
        end
        local is_provider = false

        -- if message_level >= 3 then printmsg({"ltn-message.train-arrived", tostring(trainName), stop_name}, trainForce, false) end
        if message_level >= 3 then
            printmsg({ 'ltn-message.train-arrived', Make_Train_RichText(train, nil), format('[train-stop=%d]', stopID) }, trainForce, false)
        end
        if debug_log then
            log(format('(TrainArrives) Train [%d] \"%s\": arrived at LTN-stop [%d] \"%s\"; train_faces_stop: %s', train.id, trainName, stopID, stop_name,
                stop.parked_train_faces_stop))
        end

        if stop.error_code == 0 then
            if stop.is_depot then
                local delivery = storage.Dispatcher.Deliveries[train.id]
                if delivery then
                    -- delivery should have been removed when leaving requester. Handle like delivery timeout.
                    local from_entity = storage.LogisticTrainStops[delivery.from_id] and storage.LogisticTrainStops[delivery.from_id].entity
                    local to_entity = storage.LogisticTrainStops[delivery.to_id] and storage.LogisticTrainStops[delivery.to_id].entity
                    if message_level >= 1 then
                        printmsg({
                            'ltn-message.delivery-removed-depot',
                            Make_Stop_RichText(from_entity) or delivery.from,
                            Make_Stop_RichText(to_entity) or delivery.to
                        }, delivery.force, false)
                    end
                    if debug_log then
                        log(format('(TrainArrives) Train [%d] \"%s\": Entered Depot with active Delivery. Failing Delivery and reseting train.',
                            train.id, trainName))
                    end
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
                if table_size(train_fluids) > 0 and depot_fluid_cleaning > 0 then
                    -- cleaning per wagon
                    for i, wagon in pairs(train.fluid_wagons) do
                        for fluid, count in pairs(wagon.get_fluid_contents()) do
                            if count <= depot_fluid_cleaning then
                                local removed = wagon.remove_fluid { name = fluid, amount = count }
                                if debug_log then log(format('(TrainArrives) Train \"%s\"[%d]: Depot fluid removal %s %f/%f', trainName, i, fluid, removed, count)) end
                            end
                        end
                    end
                    -- cleaning whole train doesn't work in 1.1.26
                    -- for fluid, count in pairs(train_fluids) do
                    --   if count <= depot_fluid_cleaning then
                    --     local removed = train.remove_fluid({name=fluid, amount=count})
                    --     log(format("Train %s: removed %s %f/%f", trainName, fluid, removed, count))
                    --   end
                    -- end
                    train_fluids = train.get_fluid_contents()
                end

                -- check for leftover cargo
                if table_size(train_items) > 0 then
                    create_alert(stop.entity, 'cargo-warning', { 'ltn-message.depot_left_over_cargo', trainName, stop_name }, trainForce)
                end
                if table_size(train_fluids) > 0 then
                    create_alert(stop.entity, 'cargo-warning', { 'ltn-message.depot_left_over_cargo', trainName, stop_name }, trainForce)
                end

                -- make train available for new deliveries
                local capacity, fluid_capacity = GetTrainCapacity(train)
                storage.Dispatcher.availableTrains[train.id] = {
                    train = train,
                    surface = loco.surface,
                    force = trainForce,
                    depot_priority = stop.depot_priority,
                    network_id = stop.network_id,
                    capacity = capacity,
                    fluid_capacity = fluid_capacity
                }
                storage.Dispatcher.availableTrains_total_capacity = storage.Dispatcher.availableTrains_total_capacity + capacity
                storage.Dispatcher.availableTrains_total_fluid_capacity = storage.Dispatcher.availableTrains_total_fluid_capacity + fluid_capacity
                -- log("added available train "..train.id..", inventory: "..tostring(storage.Dispatcher.availableTrains[train.id].capacity)..", fluid capacity: "..tostring(storage.Dispatcher.availableTrains[train.id].fluid_capacity))

                -- reset schedule
                ---@type TrainSchedule
                local schedule = {
                    current = 1,

                    records = {
                        NewScheduleRecord {
                            stationName = stop_name,
                            condType = 'inactivity',
                            ticks = depot_inactivity
                        }
                    }
                }

                train.schedule = schedule

                -- reset filters and bars
                if depot_reset_filters and train.cargo_wagons then
                    for n, wagon in pairs(train.cargo_wagons) do
                        local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
                        if inventory then
                            if inventory.is_filtered() then
                                -- log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory).." filtered slots.")
                                for slotIndex = 1, #inventory, 1 do
                                    inventory.set_filter(slotIndex, nil)
                                end
                            end
                            if inventory.supports_bar and #inventory - inventory.get_bar() > 0 then
                                -- log("Cargo-Wagon["..tostring(n).."]: reseting "..tostring(#inventory - inventory.get_bar()).." locked slots.")
                                inventory.set_bar()
                            end
                        end
                    end
                end

                setLamp(stop, 'blue', 1)
            else -- stop is no Depot
                -- check requester for incorrect shipment
                local delivery = storage.Dispatcher.Deliveries[train.id]
                if delivery then
                    is_provider = delivery.from_id == stop.entity.unit_number
                    if delivery.to_id == stop.entity.unit_number then
                        local requester_unscheduled_cargo = false

                        ---@type ltn.Shipment
                        local unscheduled_load = {}
                        for _, item in pairs(train.get_contents()) do
                            local typed_name = 'item,' .. item.name
                            if not delivery.shipment[typed_name] then
                                requester_unscheduled_cargo = true
                                unscheduled_load[typed_name] = item.count
                            end
                        end
                        local train_fluids = train.get_fluid_contents()
                        for name, count in pairs(train_fluids) do
                            local typed_name = 'fluid,' .. name
                            if not delivery.shipment[typed_name] then
                                requester_unscheduled_cargo = true
                                unscheduled_load[typed_name] = count
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
                end

                -- set lamp to blue for LTN controlled trains
                for i = 1, #stop.active_deliveries, 1 do
                    if stop.active_deliveries[i] == train.id then
                        setLamp(stop, 'blue', #stop.active_deliveries)
                        break
                    end
                end
            end
        end

        UpdateStopOutput(stop, is_provider and not (provider_show_existing_cargo))
    end
end

-- update stop output when train leaves stop
-- when called from on_train_created stoppedTrain.train will be invalid
function TrainLeaves(trainID)
    local stoppedTrain = storage.StoppedTrains[trainID] -- checked before every call of TrainLeaves
    local train = stoppedTrain.train
    local stopID = stoppedTrain.stopID
    local stop = storage.LogisticTrainStops[stopID]
    if not stop then
        if debug_log then log(format('(TrainLeaves) Error: StopID [%d] not found in storage.LogisticTrainStops', stopID)) end
        storage.StoppedTrains[trainID] = nil
        return
    end
    if not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
        if debug_log then log(format('(TrainLeaves) Error: StopID [%d] contains invalid entity. Processing skipped, train inventory not updated.', stopID)) end
        storage.StoppedTrains[trainID] = nil
        -- don't call RemoveStop here as RemoveStop calls TrainLeaves again
        return
    end
    local stop_name = stop.entity.backer_name

    -- train was stopped at LTN depot
    if stop.is_depot then
        if storage.Dispatcher.availableTrains[trainID] then -- trains are normally removed when deliveries are created
            storage.Dispatcher.availableTrains_total_capacity = storage.Dispatcher.availableTrains_total_capacity -
                storage.Dispatcher.availableTrains[trainID].capacity
            storage.Dispatcher.availableTrains_total_fluid_capacity = storage.Dispatcher.availableTrains_total_fluid_capacity -
                storage.Dispatcher.availableTrains[trainID].fluid_capacity
            storage.Dispatcher.availableTrains[trainID] = nil
        end
        if stop.error_code == 0 then
            setLamp(stop, 'green', 1)
        end
        if debug_log then log(format('(TrainLeaves) Train [%d] \"%s\": left Depot [%d] \"%s\".', trainID, stoppedTrain.name, stopID, stop.entity.backer_name)) end

        -- train was stopped at LTN stop
    else
        -- remove delivery from stop
        for i = #stop.active_deliveries, 1, -1 do
            if stop.active_deliveries[i] == trainID then
                table.remove(stop.active_deliveries, i)
            end
        end

        local delivery = storage.Dispatcher.Deliveries[trainID]
        if train.valid and delivery then
            if delivery.from_id == stop.entity.unit_number then
                -- update delivery counts to train inventory
                local actual_load = {}
                local unscheduled_load = {}
                local provider_unscheduled_cargo = false
                local provider_missing_cargo = false
                for _, item in pairs(train.get_contents()) do
                    local typed_name = 'item,' .. item.name
                    local planned_count = delivery.shipment[typed_name]
                    if planned_count then
                        actual_load[typed_name] = item.count -- update shipment to actual inventory
                        if item.count < planned_count then
                            -- underloaded
                            provider_missing_cargo = true
                        end
                    else
                        -- loaded wrong items
                        unscheduled_load[typed_name] = item.count
                        provider_unscheduled_cargo = true
                    end
                end
                local train_fluids = train.get_fluid_contents()
                for name, count in pairs(train_fluids) do
                    local typed_name = 'fluid,' .. name
                    local planned_count = delivery.shipment[typed_name]
                    if planned_count then
                        actual_load[typed_name] = count     -- update shipment actual inventory
                        if planned_count - count > 0.1 then -- prevent lsb errors
                            -- underloaded
                            provider_missing_cargo = true
                        end
                    else
                        -- loaded wrong fluids
                        unscheduled_load[typed_name] = count
                        provider_unscheduled_cargo = true
                    end
                end
                delivery.pickupDone = true -- remove reservations from this delivery
                if debug_log then
                    log(format('(TrainLeaves) Train [%d] \"%s\": left Provider [%d] \"%s\"; cargo: %s; unscheduled: %s ', trainID,
                        stoppedTrain.name, stopID, stop.entity.backer_name, serpent.line(actual_load), serpent.line(unscheduled_load)))
                end
                storage.StoppedTrains[trainID] = nil

                if provider_missing_cargo then
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.provider_missing_cargo', stoppedTrain.name, stop_name }, stoppedTrain.force)

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
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.provider_unscheduled_cargo', stoppedTrain.name, stop_name }, stoppedTrain.force)

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
                if requester_delivery_reset and train.schedule then
                    ---@type TrainSchedule
                    local schedule = {
                        current = 1,

                        records = {
                            NewScheduleRecord {
                                stationName = train.schedule.records[1].station,
                                condType = 'inactivity',
                                ticks = depot_inactivity
                            }
                        }
                    }

                    train.schedule = schedule
                end

                local remaining_load = {}
                local requester_left_over_cargo = false
                for _, item in pairs(train.get_contents()) do
                    -- not fully unloaded
                    local typed_name = 'item,' .. item.name
                    requester_left_over_cargo = true
                    remaining_load[typed_name] = item.count
                end
                local train_fluids = train.get_fluid_contents()
                for name, count in pairs(train_fluids) do
                    -- not fully unloaded
                    local typed_name = 'fluid,' .. name
                    requester_left_over_cargo = true
                    remaining_load[typed_name] = count
                end

                if debug_log then
                    log(format('(TrainLeaves) Train [%d] \"%s\": left Requester [%d] \"%s\" with left over cargo: %s', trainID, stoppedTrain.name,
                        stopID, stop.entity.backer_name, serpent.line(remaining_load)))
                end
                -- signal completed delivery and remove it
                if requester_left_over_cargo then
                    create_alert(stop.entity, 'cargo-alert', { 'ltn-message.requester_left_over_cargo', stoppedTrain.name, stop_name }, stoppedTrain.force)

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
                if debug_log then
                    log(format('(TrainLeaves) Train [%d] \"%s\": left LTN-stop [%d] \"%s\".', trainID, stoppedTrain.name, stopID,
                        stop.entity.backer_name))
                end
            end
        end
        if stop.error_code == 0 then
            if #stop.active_deliveries > 0 then
                setLamp(stop, 'yellow', #stop.active_deliveries)
            else
                setLamp(stop, 'green', 1)
            end
        end
    end

    -- remove train reference
    stop.parked_train = nil
    stop.parked_train_id = nil
    -- if message_level >= 3 then printmsg({"ltn-message.train-left", tostring(stoppedTrain.name), stop.entity.backer_name}, stoppedTrain.force) end
    if message_level >= 3 then
        printmsg({ 'ltn-message.train-left', Make_Train_RichText(train, stoppedTrain.name), format('[train-stop=%d]', stopID) },
            stoppedTrain.force, false)
    end
    UpdateStopOutput(stop)

    storage.StoppedTrains[trainID] = nil
end

-- local reverse_defines = require('__flib__.reverse-defines')

function OnTrainStateChanged(event)
    -- log(game.tick.." (OnTrainStateChanged) Train name: "..tostring(Get_Train_Name(event.train))..", train.id:"..tostring(event.train.id).." stop: "..tostring(event.train.station and event.train.station.backer_name)..", state: "..reverse_defines.train_state[event.old_state].." > "..reverse_defines.train_state[event.train.state] )
    local train = event.train
    if train.state == defines.train_state.wait_station and train.station ~= nil and ltn_stop_entity_names[train.station.name] then
        TrainArrives(train)
    elseif event.old_state == defines.train_state.wait_station and storage.StoppedTrains[train.id] then -- update to 0.16
        TrainLeaves(train.id)
    end
end

-- updates or removes delivery references
function Update_Delivery(old_train_id, new_train)
    local delivery = storage.Dispatcher.Deliveries[old_train_id]

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

    -- copy storage.Dispatcher.Deliveries[old_train_id] to new_train.id and change attached train in delivery
    if delivery then
        delivery.train = new_train
        storage.Dispatcher.Deliveries[new_train.id] = delivery
    end

    if storage.StoppedTrains[old_train_id] then
        TrainLeaves(old_train_id) -- removal only, new train is added when on_train_state_changed fires with wait_station afterwards
    end
    storage.Dispatcher.Deliveries[old_train_id] = nil

    return delivery
end

function OnTrainCreated(event)
    -- log("(on_train_created) Train name: "..tostring(Get_Train_Name(event.train))..", train.id:"..tostring(event.train.id)..", .old_train_id_1:"..tostring(event.old_train_id_1)..", .old_train_id_2:"..tostring(event.old_train_id_2)..", state: "..tostring(event.train.state))
    -- on_train_created always sets train.state to 9 manual, scripts have to set the train back to its former state.

    if event.old_train_id_1 then
        Update_Delivery(event.old_train_id_1, event.train)
    end

    if event.old_train_id_2 then
        Update_Delivery(event.old_train_id_2, event.train)
    end
end
