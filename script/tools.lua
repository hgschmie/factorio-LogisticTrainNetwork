-----------------------------------------------------------------------
-- tools
-----------------------------------------------------------------------

---@class ltn.Tools
local Tools = {}

-----------------------------------------------------------------------
-- typed accessors to storage
-----------------------------------------------------------------------

--- Typed access to the dispatcher instance from storage.
---
---@return ltn.Dispatcher
function Tools.getDispatcher()
    return storage.Dispatcher
end

--- Typed access to the stopped trains from storage.
---
---@return table<number, ltn.StoppedTrain>
function Tools.getStoppedTrains()
    return storage.StoppedTrains
end

-----------------------------------------------------------------------
-- Item Identifier management
-----------------------------------------------------------------------

--- Convert a Signal into a typed item string
---@param signal SignalID
---@return ltn.ItemIdentifier
function Tools.createItemIdentifier(signal)
    assert(signal)
    return (signal.type or 'item')
        .. ',' .. signal.name
    -- .. ',' .. (signal.quality or 'normal')
end

---@param identifier ltn.ItemIdentifier
---@return SignalID Guaranteed to have all fields filled.
function Tools.parseItemIdentifier(identifier)
    assert(identifier)
    local type, name, quality = identifier:match('^([^,]+),([^,]+),?([^,]*)')
    assert(#name > 0)

    return {
        type = type or 'item',
        name = name,
        quality = quality or 'normal',
    }
end

-----------------------------------------------------------------------
-- Locomotives and Wagons
-----------------------------------------------------------------------

--- Get the main locomotive in a given train. -- from flib
--- @param train LuaTrain
--- @return LuaEntity? locomotive The primary locomotive entity or `nil` when no locomotive was found
function Tools.getMainLocomotive(train)
    if not train.valid then return end
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

---@param entity LuaEntity
---@return number
function Tools.getCargoWagonCapacity(entity)
    local capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon) or 0
    storage.WagonCapacity[entity.name] = capacity
    return capacity
end

---@param entity LuaEntity
---@return number
function Tools.getFluidWagonCapacity(entity)
    local capacity = entity.prototype.fluid_capacity
    storage.WagonCapacity[entity.name] = capacity
    return capacity
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
            local capacity = storage.WagonCapacity[wagon.name] or Tools.getCargoWagonCapacity(wagon)
            inventorySize = inventorySize + capacity
        end
        for _, wagon in pairs(train.fluid_wagons) do
            local capacity = storage.WagonCapacity[wagon.name] or Tools.getFluidWagonCapacity(wagon)
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

    if message_include_gps then
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
        return string.format('[train=%d] %s', train.id, train_name)
    end
end

return Tools
