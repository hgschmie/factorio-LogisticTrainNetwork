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
-- print messages
-----------------------------------------------------------------------

---@type PrintSettings
local settings = {
    sound = defines.print_sound.use_player_settings,
    skip = defines.print_skip.if_visible,
}

--- write msg to console for all member of force or all players
---@param msg LocalisedString
---@param force LuaForce?
function Tools.printmsg(msg, force)
    if force and force.valid then
        force.print(msg, settings)
    else
        game.print(msg, settings)
    end
end

-----------------------------------------------------------------------
-- Item Identifier management
-----------------------------------------------------------------------

--- Convert a Signal into a typed item string. If the quality is 'normal',
--- omit quality information
---@param signal SignalID
---@return ltn.ItemIdentifier
function Tools.createItemIdentifier(signal)
    assert(signal)
    return table.concat({
        signal.type or 'item',
        signal.name,
        signal.quality and signal.quality ~= 'normal' and signal.quality or nil
    }, ',')
end

--- Convert a ItemWithQualityCounts into a typed item string
---@param item ItemWithQualityCounts
---@return ltn.ItemIdentifier
function Tools.createItemIdentifierFromItemWithQualityCounts(item)
    assert(item)
    return Tools.createItemIdentifier {
        type = 'item',
        name = item.name,
        quality = item.quality
    }
end

--- Convert a fluid name into a typed item string
---@param fluid_name string
---@return ltn.ItemIdentifier
function Tools.createItemIdentifierFluidName(fluid_name)
    assert(fluid_name)
    return Tools.createItemIdentifier {
        type = 'fluid',
        name = fluid_name,
    }
end

---@param identifier ltn.ItemIdentifier
---@return SignalID? Guaranteed to have all fields filled.
function Tools.parseItemIdentifier(identifier)
    if not identifier then return nil end
    local type, name, quality = identifier:match('^([^,]+),([^,]+),?([^,]*)')

    if not name or #name == 0 then return nil end
    if not (prototypes.item[name] or prototypes.fluid[name]) then return nil end

    return {
        type = type or 'item',
        name = name,
        quality = (quality and #quality > 0) and quality or 'normal',
    }
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

--- Create backwards compatible loading list for API use.
---@param loadingList ltn.ItemLoadingElement[]
---@return ltn.LoadingList
function Tools.createLoadingList(loadingList)
    ---@type ltn.ItemLoadingElement[]
    local result = {}

    for _, element in pairs(loadingList) do
        table.insert(result, {
            name = element.item.name,
            type = element.item.type,
            quality = element.item.quality,
            count = element.count,
            localname = element.localname,
            stacks = element.stacks,
        })
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
