--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 * Control stage utility functions
 *
 * See LICENSE.md in the project directory for license information.
--]]

local Get_Main_Locomotive = require('__flib__.train').get_main_locomotive

---@param entity LuaEntity
---@return number
local function getCargoWagonCapacity(entity)
    local capacity = entity.prototype.get_inventory_size(defines.inventory.cargo_wagon) or 0
    -- log("(getCargoWagonCapacity) capacity for "..entity.name.." = "..capacity)
    storage.WagonCapacity[entity.name] = capacity
    return capacity
end

---@param entity LuaEntity
---@return number
local function getFluidWagonCapacity(entity)
    local capacity = entity.prototype.fluid_capacity
    -- log("(getFluidWagonCapacity) capacity for "..entity.name.." = "..capacity)
    storage.WagonCapacity[entity.name] = capacity
    return capacity
end

-- returns inventory and fluid capacity of a given train
---@param train LuaTrain
function GetTrainCapacity(train)
    local inventorySize = 0
    local fluidCapacity = 0
    if train and train.valid then
        for _, wagon in pairs(train.cargo_wagons) do
            local capacity = storage.WagonCapacity[wagon.name] or getCargoWagonCapacity(wagon)
            inventorySize = inventorySize + capacity
        end
        for _, wagon in pairs(train.fluid_wagons) do
            local capacity = storage.WagonCapacity[wagon.name] or getFluidWagonCapacity(wagon)
            fluidCapacity = fluidCapacity + capacity
        end
    end
    return inventorySize, fluidCapacity
end

-- returns rich text string for train stops, or nil if entity is invalid
---@param entity LuaEntity
---@return string?
function Make_Stop_RichText(entity)
    if not (entity and entity.valid) then return nil end

    if message_include_gps then
        return string.format('[train-stop=%d] [gps=%s,%s,%s]', entity.unit_number, entity.position['x'], entity.position['y'], entity.surface.name)
    else
        return string.format('[train-stop=%d]', entity.unit_number)
    end
end

---@param train LuaTrain
---@param train_name string
function Make_Train_RichText(train, train_name)
    local loco = Get_Main_Locomotive(train)
    if loco and loco.valid then
        return string.format('[train=%d] %s', loco.unit_number, train_name or loco.backer_name)
    else
        return string.format('[train=%d] %s', train.id, train_name)
    end
end
