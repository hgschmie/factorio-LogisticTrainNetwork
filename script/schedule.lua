-----------------------------------------------------------------------
-- Manage all schedule related things
-----------------------------------------------------------------------

local util = require('util')
local tools = require('script.tools')

---@class ltn.ScheduleManager
local ScheduleManager = {}

---@class ltn.Record : SignalID
---@field provider boolean
---@field requester boolean
---@field count number

---@param wait_conditions WaitCondition[]
---@return table<string, ltn.Record>
function ScheduleManager:analyzeRecord(wait_conditions)
    local result = {}
    for _, wait_condition in pairs(wait_conditions) do
        if (wait_condition.type == 'item_count' or wait_condition.type == 'fluid_count') and wait_condition.condition and wait_condition.condition.first_signal then
            local record = {
                name = wait_condition.condition.first_signal.name,
                type = wait_condition.condition.first_signal.type or 'item',
                quality = wait_condition.condition.first_signal.quality or 'normal',
                provider = wait_condition.condition.comparator == '≥',
                requester = (wait_condition.condition.comparator == '=' and wait_condition.condition.constant == 0),
                count = wait_condition.condition.constant
            }
            assert(record.name)

            if record.provider or record.requester then
                local key = tools.createItemIdentifier(record)
                result[key] = record
            else
                if message_level >= 1 then tools.printmsg { 'ltn-message.error-invalid-schedule-record', record.name, record.type, record.count } end
                if debug_log then log(string.format('(AnalyzeRecord) Invalid Schedule Record: %s / %s / %d', record.name, record.type, record.count)) end
            end
        end
    end
    return result
end

---@param train LuaTrain
---@param inventory ltn.InventoryType
---@param fluidInventory ltn.FluidInventoryType
function ScheduleManager:updateFromSchedule(train, inventory, fluidInventory)
    local train_schedule = train.get_schedule()
    local wait_conditions = train_schedule.get_wait_conditions { schedule_index = train_schedule.current }
    if not wait_conditions then return end

    local results = self:analyzeRecord(wait_conditions)

    for _, result in pairs(results) do
        if result.type == 'item' then
            if result.provider then
                inventory[result.name] = inventory[result.name] or {
                    name = result.name,
                    quality = result.quality,
                    count = 0,
                }

                inventory[result.name].count = inventory[result.name].count + result.count
            else
                inventory[result.name] = nil
            end
        elseif result.type == 'fluid' then
            fluidInventory[result.name] = result.provider and ((fluidInventory[result.name] or 0) + result.count) or -1
        end
    end
end

---@param train LuaTrain
---@param network_id integer
---@return ltn.TrainStop? train_stop A depot train stop
function ScheduleManager:findDepot(train, network_id)
    local all_stops = tools.getAllStops()
    local all_depots = tools.findMatchingStops(tools.getDepots(), network_id)
    if table_size(all_depots) == 0 then return nil end

    if not LtnSettings.reselect_depot then
        local train_schedule = train.get_schedule()
        if train_schedule.get_record_count() > 0 then
            local depot_record = train_schedule.get_record { schedule_index = 1, }
            if depot_record and depot_record.station then
                for _, depot in pairs(all_depots) do
                    if depot.entity.backer_name == depot_record.station and all_stops[depot.entity.unit_number] then
                        return all_stops[depot.entity.unit_number]
                    end
                end
            end
        end
    end

    -- no depot found / reselection requested

    ---@type LuaEntity[]
    local depots = {}
    for _, depot in pairs(all_depots) do
        table.insert(depots, depot.entity)
    end

    local path_results = game.train_manager.request_train_path {
        type = 'all-goals-accessible',
        train = train,
        goals = depots,
    }

    if path_results.amount_accessible == 0 then return nil end
    ---@type ltn.TrainStop[]
    local accessible_stations = {}

    for idx, accessible in pairs(path_results.accessible) do
        if accessible then
            table.insert(accessible_stations, all_stops[depots[idx].unit_number])
        end
    end

    return accessible_stations[math.random(#accessible_stations)]
end

---@param train LuaTrain
---@param network_id integer
---@return ltn.TrainStop? train_stop A fuel station train stop
function ScheduleManager:findFuelStation(train, network_id)
    local all_stops = tools.getAllStops()
    local all_fuel_stations = tools.findMatchingStops(tools.getFuelStations(), network_id)
    if table_size(all_fuel_stations) == 0 then return nil end

    ---@type LuaEntity[]
    local stations = {}
    for _, station in pairs(all_fuel_stations) do
        if station.fuel_signals then -- must provide some threshold signal
            table.insert(stations, station.entity)
        end
    end

    ---@type TrainPathFinderOneGoalResult
    local path_result = game.train_manager.request_train_path {
        type = 'any-goal-accessible',
        train = train,
        goals = stations,
    }

    if not path_result.found_path then return nil end
    return all_stops[stations[path_result.goal_index].unit_number]
end

---@param train LuaTrain
function ScheduleManager:resetInterrupts(train)
    if not LtnSettings.reset_interrupts then return end

    local train_schedule = train.get_schedule()

    if not LtnSettings.enable_fuel_stations then
        train_schedule.clear_interrupts()
        return
    end

    for i = train_schedule.interrupt_count, 1, -1 do
        local interrupt = train_schedule.get_interrupt(i)
        if interrupt and interrupt.name ~= LTN_INTERRUPT_NAME then
            train_schedule.remove_interrupt(i)
        end
    end
end

---@param train_schedule LuaSchedule
---@param name string
---@return integer?
local function find_interrupt_index(train_schedule, name)
    for i = 1, train_schedule.interrupt_count do
        local interrupt = train_schedule.get_interrupt(i)
        if interrupt and interrupt.name == name then return i end
    end
    return nil
end

---@param train LuaTrain
function ScheduleManager:removeFuelInterrupt(train)
    local train_schedule = train.get_schedule()
    local interrupt_index = find_interrupt_index(train_schedule, LTN_INTERRUPT_NAME)
    if interrupt_index then train_schedule.remove_interrupt(interrupt_index) end
end

---@param train LuaTrain
---@param network_id integer
function ScheduleManager:updateFuelInterrupt(train, network_id)
    local fuel_station = self:findFuelStation(train, network_id)
    local train_schedule = train.get_schedule()

    local interrupt_index = find_interrupt_index(train_schedule, LTN_INTERRUPT_NAME)

    if LtnSettings.enable_fuel_stations and fuel_station then
        assert(fuel_station.fuel_signals)

        ---@type WaitCondition[]
        local interrupt_conditions = {}

        for _, circuit_condition in pairs(fuel_station.fuel_signals) do
            table.insert(interrupt_conditions, {
                type = 'fuel_item_count_any',
                condition = util.copy(circuit_condition),
                compare_type = 'or',
            })
            table.insert(interrupt_conditions, {
                type = 'fuel_item_count_any',
                condition = {
                    comparator = '>',
                    first_signal = util.copy(circuit_condition.first_signal),
                    constant = 0,
                },
                compare_type = 'and',
            })
        end

        ---@type ScheduleInterrupt
        local schedule_interrupt = {
            name = LTN_INTERRUPT_NAME,
            inside_interrupt = false,
            conditions = interrupt_conditions,
            targets = {
                {
                    station = fuel_station.entity.backer_name,
                    wait_conditions = {
                        {
                            type = 'inactivity',
                            ticks = 120,
                        },
                        {
                            type = 'fuel_full',
                            compare_type = 'or',
                        },

                    },
                    temporary = true,
                    allows_unloading = false,
                }
            }
        }

        if interrupt_index then
            train_schedule.change_interrupt(interrupt_index, schedule_interrupt)
        else
            train_schedule.add_interrupt(schedule_interrupt)
        end
    else
        -- no fuel station in the network
        if interrupt_index then train_schedule.remove_interrupt(interrupt_index) end
    end
end

--- Adds a stop for a depot
---@param train LuaTrain
---@param stop ltn.TrainStop
---@param inactivity number
---@param reset boolean?
function ScheduleManager:depotStop(train, stop, inactivity, reset)
    local train_schedule = train.get_schedule()
    local count = train_schedule.get_record_count()

    -- if the schedule should not be reset and there are stops on the schedule, do nothing
    if not reset and count > 0 then return end

    train.group = ''

    if count > 0 then
        -- remove all but the first stop (which is the depot)
        for index = count, 2, -1 do
            train_schedule.remove_record { schedule_index = index }
        end
        local first_stop = assert(train_schedule.get_record { schedule_index = 1 })

        -- If the stop is the expected depot, do not modify the schedule further
        -- otherwise, the schedule is invalid enough that other mods will not receive a
        -- on_train_state_changed with train.state == wait_station event which may throw
        -- other mods off -- see https://forums.factorio.com/viewtopic.php?t=130803
        if first_stop.station == stop.entity.backer_name then return end

        -- first station was unexpected. Clear the depot record as well.
        train_schedule.remove_record { schedule_index = 1 }
    end

    -- schedule was either empty or the depot stop was not the right stop
    -- add a new depot stop
    train_schedule.add_record {
        station = stop.entity.backer_name,
        temporary = false,
        allows_unloading = true,
        wait_conditions = {
            {
                type = 'inactivity',
                ticks = inactivity,
            }
        },
    }
end

---@param train LuaTrain
---@param rail LuaEntity
---@param rail_direction defines.rail_direction
---@param stop_schedule_index integer?
function ScheduleManager:temporaryStop(train, rail, rail_direction, stop_schedule_index)
    local train_schedule = train.get_schedule()

    train_schedule.add_record {
        index = stop_schedule_index and { schedule_index = stop_schedule_index, },
        temporary = true,
        rail = rail,
        rail_direction = rail_direction,
        allows_unloading = false,
        wait_conditions = {
            {
                type = 'time',
                ticks = 0,
            }
        },
    }
end

---@type WaitCondition
local RED_SIGNAL_CONDITION = {
    compare_type = 'and',
    type = 'circuit',
    condition = {
        comparator = '=',
        first_signal = {
            type = 'virtual',
            name = 'signal-red',
            quality = 'normal',
        },
        constant = 0,
    }
}

local GREEN_SIGNAL_CONDITION = {
    compare_type = 'or',
    type = 'circuit',
    condition = {
        comparator = '>=',
        first_signal = {
            type = 'virtual',
            name = 'signal-green',
            quality = 'normal',
        },
        constant = 1,
    }
}

local INACTIVITY_CONDITION = {
    compare_type = 'and',
    type = 'inactivity',
    ticks = 120,
}

---@param wait_conditions WaitCondition[]
function ScheduleManager:addControlSignals(wait_conditions)
    if LtnSettings.finish_loading then
        table.insert(wait_conditions, INACTIVITY_CONDITION)
    end

    -- with circuit control enabled keep trains waiting until red = 0 and force them out with green ≥ 1
    if LtnSettings.schedule_cc then
        table.insert(wait_conditions, RED_SIGNAL_CONDITION)
        table.insert(wait_conditions, GREEN_SIGNAL_CONDITION)
    end

    if LtnSettings.stop_timeout > 0 then -- send stuck trains away when stop_timeout is set
        table.insert(wait_conditions, { compare_type = 'or', type = 'time', ticks = LtnSettings.stop_timeout })
        -- should it also wait for red = 0?
        if LtnSettings.schedule_cc then
            table.insert(wait_conditions, RED_SIGNAL_CONDITION)
        end
    end
end

---@param train LuaTrain
---@param stop ltn.TrainStop
---@param loadingList ltn.ItemLoadingElement[]
function ScheduleManager:providerStop(train, stop, loadingList)
    local wait_conditions = {}

    for _, loadingElement in pairs(loadingList) do
        table.insert(wait_conditions, {
            compare_type = 'and',
            type = loadingElement.item.type == 'item' and 'item_count' or 'fluid_count',
            condition = {
                comparator = '>=',
                first_signal = loadingElement.item,
                constant = loadingElement.count,
            }
        })
    end

    self:addControlSignals(wait_conditions)

    local train_schedule = train.get_schedule()
    train_schedule.add_record {
        station = stop.entity.backer_name,
        temporary = false,
        allows_unloading = false,
        wait_conditions = wait_conditions,
    }
end

---@param train LuaTrain
---@param stop ltn.TrainStop
---@param loadingList ltn.ItemLoadingElement[]
function ScheduleManager:requesterStop(train, stop, loadingList)
    local wait_conditions = {}

    for _, loadingElement in pairs(loadingList) do
        table.insert(wait_conditions, {
            compare_type = 'and',
            type = loadingElement.item.type == 'item' and 'item_count' or 'fluid_count',
            condition = {
                comparator = '=',
                first_signal = loadingElement.item,
                constant = 0, -- since 1.1.0, fluids will only be 0 if empty (see https://wiki.factorio.com/Train_stop)
            }
        })
    end

    self:addControlSignals(wait_conditions)

    local train_schedule = train.get_schedule()
    train_schedule.add_record {
        station = stop.entity.backer_name,
        temporary = false,
        allows_unloading = true,
        wait_conditions = wait_conditions,
    }
end

---@param train LuaTrain
---@param index number
---@return string? stop_name
function ScheduleManager:getStopName(train, index)
    local train_schedule = train.get_schedule()
    local record = train_schedule.get_record { schedule_index = index }
    if not record then return nil end
    return record.station
end

---@param train LuaTrain
---@return boolean True if train has a schedule
function ScheduleManager:hasSchedule(train)
    local train_schedule = train.get_schedule()
    local record_count = train_schedule.get_record_count()
    return record_count and record_count > 0 or false
end

---@param train LuaTrain
---@return ScheduleRecord[] train_schedule Schedule records
---@return integer current
function ScheduleManager:getSchedule(train)
    local train_schedule = train.get_schedule()
    local records = train_schedule.get_records() or {}
    return records, train_schedule.current
end

return ScheduleManager
