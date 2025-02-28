-----------------------------------------------------------------------
-- Manage all schedule related things
-----------------------------------------------------------------------

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
        if wait_condition.condition and wait_condition.condition.first_signal then
            local record = {
                name = wait_condition.condition.first_signal.name,
                type = wait_condition.condition.first_signal.type or 'item',
                quality = wait_condition.condition.first_signal.quality or 'normal',
                provider = wait_condition.condition.comparator == '≥',
                requester = (wait_condition.condition.comparator == '=' and wait_condition.condition.constant == 0),
                count = wait_condition.condition.constant
            }
            assert(record.name)
            assert(record.provider ~= record.requester)
            local key = tools.createItemIdentifier(record)
            result[key] = record
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

---@param train_schedule LuaSchedule
function ScheduleManager:resetSchedule(train_schedule)
    local record_count = train_schedule.get_record_count()
    if not record_count then return end
    for i = record_count, 1, -1 do
        train_schedule.remove_record { schedule_index = i }
    end
end

--- Adds a stop for a depot
---@param train LuaTrain
---@param stop_name string
---@param inactivity number
---@param reset boolean?
function ScheduleManager:depotStop(train, stop_name, inactivity, reset)
    local train_schedule = train.get_schedule()

    local count = train_schedule.get_record_count()
    if reset or count == 0 then
        self:resetSchedule(train_schedule)
        train_schedule.add_record {
            station = stop_name,
            temporary = false,
        }
        train_schedule.add_wait_condition({ schedule_index = 1 }, 1, 'inactivity') -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition({ schedule_index = 1 }, 1, {
            type = 'inactivity',
            ticks = inactivity,
        })
    end
end

---@param train LuaTrain
---@param rail LuaEntity
---@param rail_direction defines.rail_direction
---@param stop_schedule_index integer?
function ScheduleManager:temporaryStop(train, rail, rail_direction, stop_schedule_index)
    local train_schedule = train.get_schedule()

    train_schedule.add_record {
        temporary = true,
        rail = rail,
--         rail_direction = rail_direction, -- not yet supported in 2.0.37
    }

    local index = train_schedule.get_record_count()
    train_schedule.drag_record(1, index) -- https://forums.factorio.com/viewtopic.php?t=127178


    -- train_schedule.add_wait_condition({ schedule_index = index }, 1, 'time') -- see https://forums.factorio.com/viewtopic.php?t=127180
    train_schedule.change_wait_condition({ schedule_index = index }, 1, {
        type = 'time',
        ticks = 0,
    })

    if stop_schedule_index then
        train_schedule.drag_record(index, stop_schedule_index)
    end
end

---@param train LuaTrain
function ScheduleManager:addControlSignals(train)
    local train_schedule = train.get_schedule()
    local record_index = {
        schedule_index = train_schedule.get_record_count()
    }

    local idx = train_schedule.get_wait_condition_count(record_index) + 1

    if finish_loading then
        train_schedule.add_wait_condition(record_index, idx, 'inactivity') -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition(record_index, idx, {
            compare_type = 'and',
            type = 'inactivity',
            ticks = 120,
        })
        idx = idx + 1
    end

    -- with circuit control enabled keep trains waiting until red = 0 and force them out with green ≥ 1
    if schedule_cc then
        train_schedule.add_wait_condition(record_index, idx, 'circuit') -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition(record_index, idx, {
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
        })
        idx = idx + 1
        train_schedule.add_wait_condition(record_index, idx, 'circuit') -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition(record_index, idx, {
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
        })
        idx = idx + 1
    end

    if stop_timeout > 0 then -- send stuck trains away when stop_timeout is set
        train_schedule.add_wait_condition(record_index, idx, 'time')
        train_schedule.change_wait_condition(record_index, idx, condition_stop_timeout)
        idx = idx + 1
        -- should it also wait for red = 0?
        if schedule_cc then
            train_schedule.add_wait_condition(record_index, idx, 'circuit') -- see https://forums.factorio.com/viewtopic.php?t=127153
            train_schedule.change_wait_condition(record_index, idx, {
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
            })
        end
    end
end

---@param train LuaTrain
---@param stationName string
---@param loadingList ltn.ItemLoadingElement[]
function ScheduleManager:providerStop(train, stationName, loadingList)
    local train_schedule = train.get_schedule()
    train_schedule.add_record {
        station = stationName,
        temporary = false,
    }

    local record_index = {
        schedule_index = train_schedule.get_record_count()
    }

    for idx, loadingElement in pairs(loadingList) do
        ---@type WaitConditionType
        local wait_condition_type = loadingElement.item.type == 'item' and 'item_count' or 'fluid_count'
        train_schedule.add_wait_condition(record_index, idx, wait_condition_type) -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition(record_index, idx, {
            compare_type = 'and',
            type = wait_condition_type,
            condition = {
                comparator = '>=',
                first_signal = loadingElement.item,
                constant = loadingElement.count,
            }
        })
    end

    self:addControlSignals(train)

    train_schedule.set_allow_unloading(record_index, false)
end

---@param train LuaTrain
---@param stationName string
---@param loadingList ltn.ItemLoadingElement[]
function ScheduleManager:requesterStop(train, stationName, loadingList)
    local train_schedule = train.get_schedule()
    train_schedule.add_record {
        station = stationName,
        temporary = false,
    }

    local record_index = {
        schedule_index = train_schedule.get_record_count()
    }

    for idx, loadingElement in pairs(loadingList) do
        local wait_condition_type = loadingElement.item.type == 'item' and 'item_count' or 'fluid_count'
        train_schedule.add_wait_condition(record_index, idx, wait_condition_type) -- see https://forums.factorio.com/viewtopic.php?t=127153
        train_schedule.change_wait_condition(record_index, idx, {
            compare_type = 'and',
            type = wait_condition_type,
            condition = {
                comparator = '=',
                first_signal = loadingElement.item,
                constant = 0, -- since 1.1.0, fluids will only be 0 if empty (see https://wiki.factorio.com/Train_stop)
            }
        })
    end

    self:addControlSignals(train)

    train_schedule.set_allow_unloading(record_index, true)
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
    ---@type ScheduleRecord[]
    local records = {}
    local record_count = train_schedule.get_record_count()

    if record_count then
        for i = 1, record_count, 1 do
            table.insert(records, train_schedule.get_record { schedule_index = i })
        end
    end
    return records, train_schedule.current
end

return ScheduleManager
