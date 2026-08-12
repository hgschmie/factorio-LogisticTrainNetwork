-----------------------------------------------------------------------
-- tools
-----------------------------------------------------------------------

---@class ltn.Tools
local Tools = {}

---@enum ltn.TickState
ltn_tick_state = {
    reset = 0,
    update_stops = 1,
    update_deliveries = 2,
    dispatch_trains = 3,
    api_events = 4,
    cleanup = 5,
}

-----------------------------------------------------------------------
-- typed accessors to storage
-----------------------------------------------------------------------

--- Typed access to the dispatcher instance from storage.
---
---@return ltn.Dispatcher
function Tools.getDispatcher()
    return assert(storage.Dispatcher)
end

--- Typed access to the stopped trains from storage.
---
---@return table<integer, ltn.StoppedTrain>
function Tools.getStoppedTrains()
    return assert(storage.StoppedTrains)
end

--- Typed access to all stops
---
---@return table<integer, ltn.TrainStop>
function Tools.getAllStops()
    return assert(storage.LogisticTrainStops)
end

--- Typed access to the fuel stops.
---@return ltn.TrainStop[][]
function Tools.getFuelStations()
    return assert(storage.FuelStations)
end

--- Typed access to the depots.
---@return ltn.TrainStop[][]
function Tools.getDepots()
    return assert(storage.Depots)
end

-----------------------------------------------------------------------
-- print messages
-----------------------------------------------------------------------

---@type PrintSettings
local settings = {
    sound = defines.print_sound.use_player_settings,
    skip = defines.print_skip.if_visible,
}

---@alias msg_func fun():LocalisedString

--- write msg to console for all member of force or all players
---@param level number
---@param msg_func msg_func
---@param target (LuaForce|LuaPlayer|LuaGameScript)?
function Tools.printmsg(level, msg_func, target)
    if LtnSettings and ((not LtnSettings.message_level) or (LtnSettings.message_level < level)) then return end

    if not target then target = game end
    target.print(msg_func(), settings)
end

-----------------------------------------------------------------------
-- logging
-----------------------------------------------------------------------

---@alias log_func fun():...

---@param level number
---@param name string
---@param msg string
---@param log_func log_func?
function Tools.log(level, name, msg, log_func)
    if LtnSettings and ((not LtnSettings.debug_log) or (LtnSettings.debug_log < level)) then return end
    log(('[LTN] (%s) [%d] - %s'):format(name, level, log_func and msg:format(log_func()) or msg))
end

-----------------------------------------------------------------------
-- Item Identifier management
-----------------------------------------------------------------------

--- Convert a Signal or a ItemWithQualityCount into a typed item string. If the quality is 'normal',
--- omit quality information
---@param item SignalID|ItemWithQualityCount
---@return ltn.ItemIdentifier
function Tools.createItemIdentifier(item)
    assert(item)
    return table.concat({
        item.type or 'item',
        item.name,
        item.quality and item.quality ~= 'normal' and item.quality or nil
    }, ',')
end

--- Convert a fluid name into a typed item string
---@param fluid_name string
---@return ltn.ItemIdentifier
function Tools.createFluidIdentifier(fluid_name)
    assert(fluid_name)
    return Tools.createItemIdentifier {
        type = 'fluid',
        name = fluid_name,
    }
end

---@param identifier ltn.ItemIdentifier
---@return SignalID? SignalID Guaranteed to have all fields filled.
function Tools.parseItemIdentifier(identifier)
    if not identifier then return nil end
    local type, name, quality = identifier:match('^([^,]+),([^,]+),?([^,]*)')

    type = type or 'item'

    if not name or #name == 0 then return nil end
    if not prototypes[type][name] then return nil end

    return {
        type = type,
        name = name,
        quality = (quality and #quality > 0) and quality or 'normal',
    }
end

--- returns the string "number1|number2" in consistent order: the smaller number is always placed first
---@param number1 number
---@param number2 number
---@return ltn.EntityPairKey
function Tools.sortedPair(number1, number2)
    return (number1 < number2) and (number1 .. '|' .. number2) or (number2 .. '|' .. number1)
end

---@param item_info SignalID
---@return string result
function Tools.prettyPrint(item_info)
    if item_info.type == 'item' then
        return string.format('[item=%s,quality=%s]', item_info.name, item_info.quality)
    else
        return string.format('[fluid=%s]', item_info.name, item_info.quality)
    end
end

---@param loading_list ltn.ItemLoadingElement[]
---@return LocalisedString result
function Tools.printLoadingList(loading_list)
    ---@type LocalisedString
    local elements = { '' }

    for _, loading_element in pairs(loading_list) do
        local sub_element = { '' }
        sub_element[#sub_element + 1] = tostring(loading_element.count)
        if loading_element.item.type == 'item' then
            sub_element[#sub_element + 1] = ' ('
            sub_element[#sub_element + 1] = { 'ltn-message.stack', loading_element.stacks }
            sub_element[#sub_element + 1] = ')'
        end

        sub_element[#sub_element + 1] = ' '
        sub_element[#sub_element + 1] = Tools.prettyPrint(loading_element.item)

        elements[#elements + 1] = sub_element
        elements[#elements + 1] = ', '

        if #elements > 18 then
            -- ensure that for extremely long mixed deliveries we don't run into the localisation print
            -- limits
            elements[#elements + 1] = '...'
            return elements
        end
    end
    if #elements > 1 then elements[#elements] = nil end

    return elements
end

--- Returns the smaller value from the StopDistance cache if it exists.
---@param distance ltn.StopDistance?
---@return number? distance
function Tools.getStopDistance(distance)
    if not distance then return nil end
    local forward_distance = (distance.distance or 0)
    local backward_distance = (distance.backwards_distance or 0)
    if forward_distance == -1 or backward_distance == -1 then return -1 end -- -1: on a different surface
    if forward_distance == 0 then return (backward_distance > 0) and backward_distance or nil end
    if backward_distance == 0 then return (forward_distance > 0) and forward_distance or nil end
    return math.min(forward_distance, backward_distance)
end

--- Create backwards compatible loading list for API use.
---@param loadingList ltn.ItemLoadingElement[]
---@return ltn.LoadingList
function Tools.createLoadingList(loadingList)
    ---@type ltn.LoadingElement[]
    local result = {}

    for _, element in pairs(loadingList) do
        result[#result + 1] = {
            name = element.item.name,
            type = element.item.type,
            quality = element.item.quality,
            count = element.count,
            localname = element.localname,
            stacks = element.stacks,
        }
    end
    return result
end

-----------------------------------------------------------------------
-- Locomotives and Wagons
-----------------------------------------------------------------------

--- Get the main locomotive in a given train. -- from flib
--- @param train LuaTrain
--- @return LuaEntity? locomotive The primary locomotive entity or `nil` when no locomotive was found
function Tools.getMainLocomotive(train)
    if not (train and train.valid) then return end
    return train.locomotives.front_movers and train.locomotives.front_movers[1] or train.locomotives.back_movers[1]
end

--- Get the backer_name of the main locomotive in a given train (which is the main train name). -- from flib
--- @param train LuaTrain
--- @return string? backer_name The backer_name of the primary locomotive or `nil` when no locomotive was found
function Tools.getTrainName(train)
    local loco = Tools.getMainLocomotive(train)
    return loco and loco.backer_name
end

--- Calculate the distance between two positions. -- from flib
--- @param pos1 MapPosition
--- @param pos2 MapPosition
--- @return number
function Tools.getDistance(pos1, pos2)
    local x1 = pos1.x or pos1[1]
    local y1 = pos1.y or pos1[2]
    local x2 = pos2.x or pos2[1]
    local y2 = pos2.y or pos2[2]
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

---@param wagon LuaEntity
---@param cap_function fun(): number?
local function get_wagon_capacity(wagon, cap_function)
    local name = wagon.name
    local quality = wagon.quality.name
    storage.WagonCapacity[name] = storage.WagonCapacity[name] or {}
    local capacity = storage.WagonCapacity[name][quality] or cap_function() or 0

    storage.WagonCapacity[name][quality] = capacity

    return capacity
end

---@param wagon LuaEntity
---@return number
function Tools.getCargoWagonCapacity(wagon)
    return get_wagon_capacity(wagon, function()
        return wagon.prototype.get_inventory_size(defines.inventory.cargo_wagon, wagon.quality)
    end)
end

---@param wagon LuaEntity
---@return number
function Tools.getFluidWagonCapacity(wagon)
    return get_wagon_capacity(wagon, function()
        local capacity = wagon.prototype.fluid_capacity
        return math.floor(capacity * (1 + 0.3 * wagon.quality.level))
    end)
end

-- returns inventory and fluid capacity of a given train
---@param train LuaTrain
---@return number inventorySize
---@return number fluidCapacity
function Tools.getTrainCapacity(train)
    local inventorySize = 0
    local fluidCapacity = 0
    if train and train.valid then
        for _, wagon in pairs(train.cargo_wagons) do
            local capacity = Tools.getCargoWagonCapacity(wagon)
            inventorySize = inventorySize + capacity
        end
        for _, wagon in pairs(train.fluid_wagons) do
            local capacity = Tools.getFluidWagonCapacity(wagon)
            fluidCapacity = fluidCapacity + capacity
        end
    end
    return inventorySize, fluidCapacity
end

-- returns rich text string for train stops, or nil if entity is invalid
---@param entity LuaEntity
---@return string?
function Tools.richTextForStop(entity)
    if not (entity and entity.valid) then return nil end

    if LtnSettings.message_include_gps then
        return string.format('[train-stop=%d] [gps=%s,%s,%s]', entity.unit_number, entity.position['x'], entity.position['y'], entity.surface.name)
    else
        return string.format('[train-stop=%d]', entity.unit_number)
    end
end

---@param train LuaTrain
---@param train_name string?
function Tools.richTextForTrain(train, train_name)
    local loco = Tools.getMainLocomotive(train)
    if loco and loco.valid then
        return string.format('[train=%d] %s', loco.unit_number, train_name or loco.backer_name)
    else
        return string.format('%s', train_name)
    end
end

local function add_result(result, left, idx)
    if not left then return end
    result[#result + 1] = (left == idx) and tostring(left) or tostring(left) .. '-' .. tostring(idx)
end

---@param network_id integer
---@return string network_list
---@return integer network_count
function Tools.networkList(network_id)
    network_id = bit32.band(network_id)

    local count = 0
    local result = {}
    local mask = 1
    local left = nil
    for idx = 1, 32 do
        if bit32.band(network_id, mask) == mask then
            count = count + 1
            if not left then left = idx end
        else
            add_result(result, left, idx - 1)
            left = nil
        end
        mask = bit32.lshift(mask, 1)
    end
    add_result(result, left, 32)

    return table.concat(result, ', ') .. (' (0x%x)'):format(network_id), count
end

-----------------------------------------------------------------------
-- Validation
-----------------------------------------------------------------------

--- Returns True if the stop exists, its main entity is valid and has a rail connected.
--- This is good enough to e.g. determine whether a stop can be used in schedule (delivery, fuel station, depot)
---@param stop (ltn.TrainStop|LuaEntity)?
---@param metrics ltn.Metrics? Tracks error state
---@return boolean is_valid
function Tools.isStopValid(stop, metrics)
    local result = false
    if stop then
        local entity = type(stop) == 'userdata' and stop or stop.entity
        result = entity.valid and entity.connected_rail and entity.connected_rail.valid and true or false
    end
    if metrics and not result then metrics:inc('invalid_stop') end

    return result
end

--- Returns True if the internal state of the train stop is consistent. Checks that all internal entities are
--- valid and functioning.
---@param stop ltn.TrainStop
---@return boolean is_consistent
function Tools.isStopConsistent(stop)
    assert(stop)
    return (stop.entity and stop.entity.valid)
        and (stop.input and stop.input.valid)
        and (stop.output and stop.output.valid)
        and (stop.lamp_control and stop.lamp_control.valid)
end

-----------------------------------------------------------------------
-- Train capacity management
-----------------------------------------------------------------------

---@param trainId number?
---@return boolean True if capacity was really reduced
function Tools.reduceAvailableCapacity(trainId)
    if not trainId then return false end

    local dispatcher = Tools.getDispatcher()

    if not dispatcher.availableTrains[trainId] then return false end

    dispatcher.knownTrains[trainId] = dispatcher.knownTrains[trainId] or {
        train = dispatcher.availableTrains[trainId].train,
        select_count = 0,
    }

    dispatcher.availableTrains_total_capacity = dispatcher.availableTrains_total_capacity - dispatcher.availableTrains[trainId].capacity
    dispatcher.availableTrains_total_fluid_capacity = dispatcher.availableTrains_total_fluid_capacity - dispatcher.availableTrains[trainId].fluid_capacity
    dispatcher.availableTrains[trainId] = nil

    return true
end

---@param train LuaTrain
---@param stop ltn.TrainStop
---@return boolean True if capacity was really increased
function Tools.increaseAvailableCapacity(train, stop)
    local dispatcher = Tools.getDispatcher()

    if dispatcher.availableTrains[train.id] then return false end

    ---@type LuaEntity?
    local loco = Tools.getMainLocomotive(train)
    ---@type LuaForce?
    local trainForce = loco and loco.force
    assert(trainForce)

    local capacity, fluid_capacity = Tools.getTrainCapacity(train)

    dispatcher.knownTrains[train.id] = dispatcher.knownTrains[train.id] or {
        train = train,
        select_count = 0,
    }

    dispatcher.availableTrains[train.id] = {
        train = train,
        surface = stop.entity.surface,
        force = trainForce,
        depot_priority = stop.depot_priority,
        network_id = stop.network_id,
        capacity = capacity,
        fluid_capacity = fluid_capacity,
        select_count = dispatcher.knownTrains[train.id].select_count,
    }

    dispatcher.availableTrains_total_capacity = dispatcher.availableTrains_total_capacity + capacity
    dispatcher.availableTrains_total_fluid_capacity = dispatcher.availableTrains_total_fluid_capacity + fluid_capacity

    return true
end

---@param train_id integer
---@return ltn.Train? The train information if the train is available
function Tools.isTrainAvailable(train_id)
    local dispatcher = Tools.getDispatcher()
    return dispatcher.availableTrains[train_id]
end

--- @param old_train_id integer? old train id
--- @param new_train LuaTrain? new train object
--- @return boolean success
function Tools.reassignTrainRecord(old_train_id, new_train)
    local dispatcher = Tools.getDispatcher()

    if not old_train_id or not (new_train and new_train.valid) then return false end

    dispatcher.knownTrains[new_train.id] = dispatcher.knownTrains[new_train.id] or {
        train = new_train,
        select_count = 0
    }

    if dispatcher.knownTrains[old_train_id] and dispatcher.knownTrains[old_train_id].select_count then
        dispatcher.knownTrains[new_train.id].select_count = dispatcher.knownTrains[new_train.id].select_count + dispatcher.knownTrains[old_train_id].select_count
    end

    return true
end

-----------------------------------------------------------------------
-- Stop List management
-----------------------------------------------------------------------

---@param stop ltn.TrainStop
---@param stop_list ltn.TrainStop[]
---@param network_id integer
function Tools.updateStopList(stop, stop_list, network_id)
    for i = 1, 32 do
        local stops = stop_list[i] or {}
        local in_network = bit32.btest(network_id, bit32.lshift(1, i - 1))
        stops[stop.entity.unit_number] = in_network and stop or nil
        stop_list[i] = stops
    end
end

--- Find all stations in the stop list that are a match for the given network id.
---@param stop_list ltn.TrainStop[]
---@param network_id integer
---@param available boolean? If true, only available stops are returned
---@return ltn.TrainStop[] train_stops Available train stops
function Tools.findMatchingStops(stop_list, network_id, available)
    local all_stops = Tools.getAllStops()
    local result = {}

    for i = 1, 32 do
        if stop_list[i] and bit32.btest(network_id, bit32.lshift(1, i - 1)) then
            for stop_id in pairs(stop_list[i]) do
                -- check if the station id is still valid
                local stop = all_stops[stop_id]
                if Tools.isStopValid(stop) then
                    result[stop_id] = stop
                else
                    stop_list[i][stop_id] = nil
                end
            end
        end
    end

    return result
end

---@param stop_list ltn.TrainStop[][]
---@param stop_id integer
function Tools.removeStop(stop_list, stop_id)
    for i = 1, 32 do
        if stop_list[i] then stop_list[i][stop_id] = nil end
    end
end

-----------------------------------------------------------------------
-- Train Stop management
-----------------------------------------------------------------------

---@param stop ltn.TrainStop
---@return boolean disabled True if the stop is disabled
function Tools.updateTrainStopSettings(stop)
    assert(stop)
    if not (stop.entity and stop.entity.valid) then return true end

    local trainstop_control = assert(stop.entity.get_or_create_control_behavior()) --[[@as LuaTrainStopControlBehavior]]

    local state = GetStationType(stop)

    if state ~= station_type.depot or LtnSettings.depot_limit_trains ~= ltn_depot_train_limit.unchanged then
        -- enable reading contents and sending signals to trains
        trainstop_control.send_to_train = true
        trainstop_control.read_from_train = true

        trainstop_control.set_trains_limit = false
        trainstop_control.trains_limit_signal = nil
    end

    if state ~= station_type.depot or LtnSettings.depot_limit_trains == ltn_depot_train_limit.reset then
        stop.entity.trains_limit = nil
    elseif LtnSettings.depot_limit_trains == ltn_depot_train_limit.set_one then
        stop.entity.trains_limit = 1
    end

    return trainstop_control.disabled
end

-----------------------------------------------------------------------
-- Manage dispatcher ticker events
-----------------------------------------------------------------------

function Tools.updateDispatchTicker()
    local stops = Tools.getAllStops()
    if next(stops) then
        -- bring up dispatcher and Train State ticker
        script.on_nth_tick(LtnSettings.dispatcher_nth_tick, OnTick)
        script.on_event(defines.events.on_train_changed_state, OnTrainStateChanged)
        script.on_event(defines.events.on_train_created, OnTrainCreated)
    else
        script.on_nth_tick(nil)
        script.on_event(defines.events.on_train_changed_state, nil)
        script.on_event(defines.events.on_train_created, nil)
    end
end

return Tools
