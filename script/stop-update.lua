--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local tools = require('script.tools')

--- return true if stop, output, lamp are on same logic network
---@param checkStop ltn.TrainStop
---@return boolean True if short circuit detected
local function detectShortCircuit(checkStop)
    local networks = {}

    for _, entity in pairs { checkStop.entity, checkStop.output, checkStop.input } do
        local entity_wires = entity.get_wire_connectors(false)
        for _, wire_connector in pairs(entity_wires) do
            if wire_connector.connection_count > 0 then
                if networks[wire_connector.network_id] then return true end
                networks[wire_connector.network_id] = entity.unit_number
            end
        end
    end

    return false
end

---@param trainID number
local function remove_available_train(trainID)
    local dispatcher = tools.getDispatcher()

    if debug_log then log(string.format('(UpdateStop) removing available train %d from depot.', trainID)) end
    dispatcher.availableTrains_total_capacity = dispatcher.availableTrains_total_capacity - dispatcher.availableTrains[trainID].capacity
    dispatcher.availableTrains_total_fluid_capacity = dispatcher.availableTrains_total_fluid_capacity - dispatcher.availableTrains[trainID].fluid_capacity
    dispatcher.availableTrains[trainID] = nil
end

-- update stop input signals
---@param stopID integer
---@param stop ltn.TrainStop
function UpdateStop(stopID, stop)
    local dispatcher = tools.getDispatcher()

    dispatcher.Requests_by_Stop[stopID] = nil

    -- remove invalid stops
    if not stop or not stop.entity.valid or not stop.input.valid or not stop.output.valid or not stop.lamp_control.valid then
        if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-stop', stopID } end
        if debug_log then log(string.format('(UpdateStop) Removing invalid stop: [%d]', stopID)) end
        RemoveStop(stopID)
        return
    end

    -- remove invalid trains
    if stop.parked_train and not stop.parked_train.valid then
        storage.LogisticTrainStops[stopID].parked_train = nil
        storage.LogisticTrainStops[stopID].parked_train_id = nil
    end

    -- remove invalid active_deliveries -- shouldn't be necessary
    for i = #stop.active_deliveries, 1, -1 do
        if not dispatcher.Deliveries[stop.active_deliveries[i]] then
            table.remove(stop.active_deliveries, i)

            if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-delivery', stop.entity.backer_name } end
            if debug_log then log(string.format("(UpdateStop) Removing invalid delivery from stop '%s': %s", stop.entity.backer_name, tostring(stop.active_deliveries[i]))) end

        end
    end

    -- reset stop parameters in case something goes wrong
    stop.min_carriages = 0
    stop.max_carriages = 0
    stop.max_trains = 0
    stop.requesting_threshold = min_requested
    stop.requester_priority = 0
    stop.no_warnings = false
    stop.providing_threshold = min_provided
    stop.provider_priority = 0
    stop.locked_slots = 0
    stop.depot_priority = 0

    -- skip short circuited stops
    if detectShortCircuit(stop) then
        stop.error_code = 1
        if stop.parked_train_id and dispatcher.availableTrains[stop.parked_train_id] then
            remove_available_train(stop.parked_train_id)
        end
        setLamp(stop, ErrorCodes[stop.error_code], 1)

        if debug_log then log(string.format('(UpdateStop) Short circuit error: %s', stop.entity.backer_name)) end

        return
    end

    -- skip deactivated stops
    local stopCB = stop.entity.get_control_behavior() --[[@as LuaTrainStopControlBehavior ]]
    if stopCB and stopCB.disabled then
        stop.error_code = 1
        if stop.parked_train_id and dispatcher.availableTrains[stop.parked_train_id] then
            remove_available_train(stop.parked_train_id)
        end
        setLamp(stop, ErrorCodes[stop.error_code], 2)

        if debug_log then log(string.format('(UpdateStop) Circuit deactivated stop: %s', stop.entity.backer_name)) end

        return
    end

    -- initialize control signal values to defaults
    local is_depot = false
    local depot_priority = 0
    local network_id = default_network
    local min_carriages = 0
    local max_carriages = 0
    local max_trains = 0
    local requesting_threshold = min_requested
    local requesting_threshold_stacks = 0
    local requester_priority = 0
    local no_warnings = false
    local providing_threshold = min_provided
    local providing_threshold_stacks = 0
    local provider_priority = 0
    local locked_slots = 0

    local signals = stop.input.get_signals(defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
    if not signals then return end -- either lamp and lampctrl are not connected or lampctrl has no output signal

    ---@type table<SignalID, number>
    local signals_filtered = {}

    for _, v in pairs(signals) do
        local signal_name = v.signal.name
        local signal_type = v.signal.type or 'item'
        if signal_name and signal_type then
            if signal_type ~= 'virtual' then
                -- add item and fluid signals to new array
                signals_filtered[v.signal] = v.count
            elseif ControlSignals[signal_name] then
                -- read out control signals
                if signal_name == ISDEPOT and v.count > 0 then
                    is_depot = true
                elseif signal_name == DEPOT_PRIORITY then
                    depot_priority = v.count
                elseif signal_name == NETWORKID then
                    network_id = v.count
                elseif signal_name == MINTRAINLENGTH and v.count > 0 then
                    min_carriages = v.count
                elseif signal_name == MAXTRAINLENGTH and v.count > 0 then
                    max_carriages = v.count
                elseif signal_name == MAXTRAINS and v.count > 0 then
                    max_trains = v.count
                elseif signal_name == REQUESTED_THRESHOLD then
                    requesting_threshold = math.abs(v.count)
                elseif signal_name == REQUESTED_STACK_THRESHOLD then
                    requesting_threshold_stacks = math.abs(v.count)
                elseif signal_name == REQUESTED_PRIORITY then
                    requester_priority = v.count
                elseif signal_name == NOWARN and v.count > 0 then
                    no_warnings = true
                elseif signal_name == PROVIDED_THRESHOLD then
                    providing_threshold = math.abs(v.count)
                elseif signal_name == PROVIDED_STACK_THRESHOLD then
                    providing_threshold_stacks = math.abs(v.count)
                elseif signal_name == PROVIDED_PRIORITY then
                    provider_priority = v.count
                elseif signal_name == LOCKEDSLOTS and v.count > 0 then
                    locked_slots = v.count
                end
            end
        end
    end

    local network_id_string = string.format('0x%x', bit32.band(network_id))

    --update lamp colors when error_code or is_depot changed state
    if stop.error_code ~= 0 or stop.is_depot ~= is_depot then
        stop.error_code = 0 -- we are error free here
        if is_depot then
            if stop.parked_train_id and stop.parked_train.valid then
                if dispatcher.Deliveries[stop.parked_train_id] then
                    setLamp(stop, 'yellow', 1)
                else
                    setLamp(stop, 'blue', 1)
                end
            else
                setLamp(stop, 'green', 1)
            end
        else
            if #stop.active_deliveries > 0 then
                if stop.parked_train_id and stop.parked_train.valid then
                    setLamp(stop, 'blue', #stop.active_deliveries)
                else
                    setLamp(stop, 'yellow', #stop.active_deliveries)
                end
            else
                setLamp(stop, 'green', 1)
            end
        end
    end

    -- check if it's a depot
    if is_depot then
        stop.is_depot = true
        stop.depot_priority = depot_priority
        stop.network_id = network_id

        -- add parked train to available trains
        if stop.parked_train_id and stop.parked_train.valid then
            if dispatcher.Deliveries[stop.parked_train_id] then

                if debug_log then log(string.format('(UpdateStop) %s {%s}, depot priority: %d, assigned train.id: %d', stop.entity.backer_name, network_id_string, depot_priority, stop.parked_train_id)) end

            else
                if not dispatcher.availableTrains[stop.parked_train_id] then
                    -- full arrival handling in case ltn-depot signal was turned on with an already parked train
                    TrainArrives(stop.parked_train)
                else
                    -- update properties from depot
                    dispatcher.availableTrains[stop.parked_train_id].network_id = network_id
                    dispatcher.availableTrains[stop.parked_train_id].depot_priority = depot_priority
                end
                if debug_log then log(string.format('(UpdateStop) %s {%s}, depot priority: %d, available train.id: %d', stop.entity.backer_name, network_id_string, depot_priority, stop.parked_train_id)) end
            end
        else
            if debug_log then log(string.format('(UpdateStop) %s {%s}, depot priority: %d, no available train', stop.entity.backer_name, network_id_string, depot_priority)) end
        end

        -- not a depot > check if the name is unique
    else
        stop.is_depot = false
        if stop.parked_train_id and dispatcher.availableTrains[stop.parked_train_id] then
            remove_available_train(stop.parked_train_id)
        end

        for signal, count in pairs(signals_filtered) do
            local signal_type = signal.type or 'item'
            local signal_name = signal.name
            local item = tools.createItemIdentifier(signal)

            for trainID, delivery in pairs(dispatcher.Deliveries) do
                local deliverycount = delivery.shipment[item]
                if deliverycount then
                    if stop.parked_train and stop.parked_train_id == trainID then
                        -- calculate items +- train inventory
                        local traincount = 0
                        if signal_type == 'fluid' then
                            traincount = math.floor(stop.parked_train.get_fluid_count(signal_name))
                        else
                            traincount = stop.parked_train.get_item_count(signal_name)
                        end

                        if delivery.to_id == stop.entity.unit_number then
                            local newcount = count + traincount
                            if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider
                            if debug_log then log(string.format('(UpdateStop) %s {%s} updating requested count with train %d inventory: %s %d+%d=%d', stop.entity.backer_name, network_id_string, trainID, item, count, traincount, newcount)) end
                            count = newcount
                        elseif delivery.from_id == stop.entity.unit_number then
                            if traincount <= deliverycount then
                                local newcount = count - (deliverycount - traincount)
                                if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request

                                if debug_log then log(string.format('(UpdateStop) %s {%s} updating provided count with train %d inventory: %s %d-%d=%d', stop.entity.backer_name, network_id_string, trainID, item, count, deliverycount - traincount, newcount)) end

                                count = newcount
                            else --train loaded more than delivery
                                if debug_log then log(string.format('(UpdateStop) %s {%s} updating delivery count with overloaded train %d inventory: %s %d', stop.entity.backer_name, network_id_string, trainID, item, traincount)) end

                                -- update delivery to new size
                                dispatcher.Deliveries[trainID].shipment[item] = traincount
                            end
                        end
                    else
                        -- calculate items +- deliveries
                        if delivery.to_id == stop.entity.unit_number then
                            local newcount = count + deliverycount
                            if newcount > 0 then newcount = 0 end --make sure we don't turn it into a provider

                            if debug_log then log(string.format('(UpdateStop) %s {%s} updating requested count with delivery: %s %d+%d=%d', stop.entity.backer_name, network_id_string, item, count, deliverycount, newcount)) end

                            count = newcount
                        elseif delivery.from_id == stop.entity.unit_number and not delivery.pickupDone then
                            local newcount = count - deliverycount
                            if newcount < 0 then newcount = 0 end --make sure we don't turn it into a request
                            if debug_log then log(string.format('(UpdateStop) %s {%s} updating provided count with delivery: %s %d-%d=%d', stop.entity.backer_name, network_id_string, item, count, deliverycount, newcount)) end
                            count = newcount
                        end
                    end
                end
            end -- for delivery

            local useProvideStackThreshold = false
            local useRequestStackThreshold = false
            local stack_count = 0

            if signal_type == 'item' then
                useProvideStackThreshold = providing_threshold_stacks > 0
                useRequestStackThreshold = requesting_threshold_stacks > 0
                if prototypes.item[signal_name] then
                    stack_count = count / prototypes.item[signal_name].stack_size
                end
            end

            -- update Dispatcher Storage
            -- Providers are used when above Provider Threshold
            -- Requests are handled when above Requester Threshold
            if (useProvideStackThreshold and stack_count >= providing_threshold_stacks) or
                (not useProvideStackThreshold and count >= providing_threshold) then
                dispatcher.Provided[item] = dispatcher.Provided[item] or {}
                dispatcher.Provided[item][stopID] = count
                dispatcher.Provided_by_Stop[stopID] = dispatcher.Provided_by_Stop[stopID] or {}
                dispatcher.Provided_by_Stop[stopID][item] = count
                if debug_log then
                    local trainsEnRoute = '';
                    for k, v in pairs(stop.active_deliveries) do
                        trainsEnRoute = trainsEnRoute .. ' ' .. v
                    end

                    log(string.format('(UpdateStop) %s {%s} provides %s %d(%d) stacks: %d(%d), priority: %d, min length: %d, max length: %d, trains en route: %s', stop.entity.backer_name, network_id_string, item, count, providing_threshold, stack_count, providing_threshold_stacks, provider_priority, min_carriages, max_carriages, trainsEnRoute))

                end
            elseif (useRequestStackThreshold and stack_count * -1 >= requesting_threshold_stacks) or
                (not useRequestStackThreshold and count * -1 >= requesting_threshold) then
                count = count * -1
                local ageIndex = item .. ',' .. stopID
                dispatcher.RequestAge[ageIndex] = dispatcher.RequestAge[ageIndex] or game.tick
                table.insert(dispatcher.Requests, {
                    age = dispatcher.RequestAge[ageIndex],
                    stopID = stopID,
                    priority = requester_priority,
                    item = item,
                    count = count
                })

                dispatcher.Requests_by_Stop[stopID] = dispatcher.Requests_by_Stop[stopID] or {}
                dispatcher.Requests_by_Stop[stopID][item] = count
                if debug_log then
                    local trainsEnRoute = table.concat(stop.active_deliveries, ', ');
                    log(string.format('(UpdateStop) %s {%s} requests %s %d(%d) stacks: %d(%d), priority: %d, min length: %d, max length: %d, age: %d/%d, trains en route: %s', stop.entity.backer_name, network_id_string, item, count, requesting_threshold, stack_count * -1, requesting_threshold_stacks, requester_priority, min_carriages, max_carriages, dispatcher.RequestAge[ageIndex], game.tick, trainsEnRoute))
                end
            end
        end -- for circuitValues

        stop.network_id = network_id
        stop.providing_threshold = providing_threshold
        stop.providing_threshold_stacks = providing_threshold_stacks
        stop.provider_priority = provider_priority
        stop.requesting_threshold = requesting_threshold
        stop.requesting_threshold_stacks = requesting_threshold_stacks
        stop.requester_priority = requester_priority
        stop.min_carriages = min_carriages
        stop.max_carriages = max_carriages
        stop.max_trains = max_trains
        stop.locked_slots = locked_slots
        stop.no_warnings = no_warnings
    end
end

---@param trainStop ltn.TrainStop
---@param color string
---@param count number
function setLamp(trainStop, color, count)
    -- skip invalid stops and colors
    if not (trainStop and trainStop.lamp_control.valid and ColorLookup[color]) then return false end

    local lampctrl_control = trainStop.lamp_control.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior ]]
    assert(lampctrl_control)
    if lampctrl_control.sections_count == 0 then
        assert(lampctrl_control.add_section())
    end

    lampctrl_control.sections[1].set_slot(1, {
        value = {
            type = 'virtual',
            name = ColorLookup[color],
            quality = 'normal',
        },
        min = count,
    })

    return true
end

---@param trainStop ltn.TrainStop
---@param ignore_existing_cargo boolean?
function UpdateStopOutput(trainStop, ignore_existing_cargo)
    -- skip invalid stop outputs
    if not trainStop.output.valid then
        return
    end

    ---@type LogisticFilter[]
    local signals = {}

    if trainStop.parked_train and trainStop.parked_train.valid then
        -- get train composition
        local carriages = trainStop.parked_train.carriages
        local encoded_positions_by_name = {}
        local encoded_positions_by_type = {}

        ---@type table<string, ItemWithQualityCounts>
        local inventory = {}
        ---@type table<string, number>
        local fluidInventory = {}

        if not (ignore_existing_cargo) then
            for _, item in pairs(trainStop.parked_train.get_contents()) do
                inventory[item.name] = item
            end
            for name, amount in pairs(trainStop.parked_train.get_fluid_contents()) do
                fluidInventory[name] = math.floor(amount)
            end
        end

        if #carriages < 32 then                       --prevent circuit network integer overflow error
            if trainStop.parked_train_faces_stop then --train faces forwards >> iterate normal
                for i = 1, #carriages do
                    local signal_type = string.format('ltn-position-any-%s', carriages[i].type)
                    if prototypes.virtual_signal[signal_type] then
                        if encoded_positions_by_type[signal_type] then
                            encoded_positions_by_type[signal_type] = encoded_positions_by_type[signal_type] + 2 ^ (i - 1)
                        else
                            encoded_positions_by_type[signal_type] = 2 ^ (i - 1)
                        end
                    else
                        if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-position-signal', signal_type } end
                        log(string.format('Error: signal \"%s\" not found!', signal_type))
                    end
                    local signal_name = string.format('ltn-position-%s', carriages[i].name)
                    if prototypes.virtual_signal[signal_name] then
                        if encoded_positions_by_name[signal_name] then
                            encoded_positions_by_name[signal_name] = encoded_positions_by_name[signal_name] + 2 ^ (i - 1)
                        else
                            encoded_positions_by_name[signal_name] = 2 ^ (i - 1)
                        end
                    else
                        if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-position-signal', signal_name } end
                        log(string.format('Error: signal \"%s\" not found!', signal_name))
                    end
                end
            else --train faces backwards >> iterate backwards
                n = 0
                for i = #carriages, 1, -1 do
                    local signal_type = string.format('ltn-position-any-%s', carriages[i].type)
                    if prototypes.virtual_signal[signal_type] then
                        if encoded_positions_by_type[signal_type] then
                            encoded_positions_by_type[signal_type] = encoded_positions_by_type[signal_type] + 2 ^ n
                        else
                            encoded_positions_by_type[signal_type] = 2 ^ n
                        end
                    else
                        if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-position-signal', signal_type } end
                        log(string.format('Error: signal \"%s\" not found!', signal_type))
                    end
                    local signal_name = string.format('ltn-position-%s', carriages[i].name)
                    if prototypes.virtual_signal[signal_name] then
                        if encoded_positions_by_name[signal_name] then
                            encoded_positions_by_name[signal_name] = encoded_positions_by_name[signal_name] + 2 ^ n
                        else
                            encoded_positions_by_name[signal_name] = 2 ^ n
                        end
                    else
                        if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-position-signal', signal_name } end
                        log(string.format('Error: signal \"%s\" not found!', signal_name))
                    end
                    n = n + 1
                end
            end

            for k, v in pairs(encoded_positions_by_type) do
                table.insert(signals, { value = { type = 'virtual', name = k, quality = 'normal', }, min = v, })
            end
            for k, v in pairs(encoded_positions_by_name) do
                table.insert(signals, { value = { type = 'virtual', name = k, quality = 'normal', }, min = v, })
            end
        end

        if not trainStop.is_depot then
            -- Update normal stations
            local conditions = trainStop.parked_train.schedule.records[trainStop.parked_train.schedule.current].wait_conditions
            if conditions ~= nil then
                for _, c in pairs(conditions) do
                    if c.condition and c.condition.first_signal then -- loading without mods can make first signal nil?
                        if c.type == 'item_count' then
                            if (c.condition.comparator == '=' and c.condition.constant == 0) then
                                --train expects to be unloaded of each of this item
                                inventory[c.condition.first_signal.name] = nil
                            elseif c.condition.comparator == '≥' then
                                --train expects to be loaded to x of this item
                                inventory[c.condition.first_signal.name] = inventory[c.condition.first_signal.name] or {
                                    name = c.condition.first_signal.name,
                                    quality = c.condition.first_signal.quality or 'normal',
                                }
                                inventory[c.condition.first_signal.name].count = c.condition.constant
                            end
                        elseif c.type == 'fluid_count' then
                            if (c.condition.comparator == '=' and c.condition.constant == 0) then
                                --train expects to be unloaded of each of this fluid
                                fluidInventory[c.condition.first_signal.name] = -1
                            elseif c.condition.comparator == '≥' then
                                --train expects to be loaded to x of this fluid
                                fluidInventory[c.condition.first_signal.name] = c.condition.constant
                            end
                        end
                    end
                end
            end

            -- output expected inventory contents
            for k, v in pairs(inventory) do
                table.insert(signals, { value = { type = 'item', name = v.name, quality = v.quality, }, min = v.count, })
            end
            for k, v in pairs(fluidInventory) do
                table.insert(signals, { value = { type = 'fluid', name = k, quality = 'normal', }, min = v, })
            end
        end -- not trainStop.is_depot
    end
    -- will reset if called with no parked train
    -- log("[LTN] "..tostring(trainStop.entity.backer_name).. " displaying "..#signals.."/"..tostring(trainStop.output.get_control_behavior().signals_count).." signals.")

    local outputControl = trainStop.output.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior ]]
    assert(outputControl)

    if outputControl.sections_count == 0 then
        assert(outputControl.add_section())
    end
    local section = outputControl.sections[1]
    section.filters = {}

    local idx = 1
    for _, signal in pairs(signals) do
        section.set_slot(idx, signal)
        idx = idx + 1
    end
end
