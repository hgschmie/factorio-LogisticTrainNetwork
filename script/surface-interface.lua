local tools = require('script.tools')

local SurfaceInterface = {}

-- removes all data about surface connections; connection owners won't be notified
function SurfaceInterface.ClearAllSurfaceConnections()
    storage.ConnectedSurfaces = {}
end

--- returns the string "number1|number2" in consistent order: the smaller number is always placed first
---@param number1 number
---@param number2 number
---@return ltn.EntityPairKey
function SurfaceInterface.SortedPair(number1, number2)
    return (number1 < number2) and (number1 .. '|' .. number2) or (number2 .. '|' .. number1)
end

--- removes the surface connection between the given entities from storage.SurfaceConnections. Does nothing if the connection doesn't exist.
---@param entity1 LuaEntity
---@param entity2 LuaEntity
function SurfaceInterface.DisconnectSurfaces(entity1, entity2)
    -- ensure received data is valid and usable
    if not (entity1 and entity1.valid and entity1.surface and entity1.surface.index and game.surfaces[entity1.surface.index]) then
        if debug_log then tools.log(5, 'DisconnectSurfaces', 'Received entity1 was invalid.') end
        return
    end
    if not (entity2 and entity2.valid and entity2.surface and entity2.surface.index and game.surfaces[entity2.surface.index]) then
        if debug_log then tools.log(5, 'DisconnectSurfaces', 'Received entity2 was invalid.') end
        return
    end

    local surface_pair_key = SurfaceInterface.SortedPair(entity1.surface.index, entity2.surface.index)

    ---@type table<ltn.EntityPairKey, ltn.SurfaceConnection>?
    local surface_connections = storage.ConnectedSurfaces[surface_pair_key]

    if surface_connections then
        local entity_pair_key = SurfaceInterface.SortedPair(entity1.unit_number, entity2.unit_number)
        if debug_log then tools.log(5, 'DisconnectSurfaces', 'removing surface connection for entities ' .. entity_pair_key .. ' between surfaces ' .. surface_pair_key) end
        surface_connections[entity_pair_key] = nil
    end
end

--- adds a surface connection between the given entities; the network_id will be used in delivery processing to discard providers that don't match the surface connection's network_id
---@param entity1 LuaEntity
---@param entity2 LuaEntity
---@param network_id string|number
function SurfaceInterface.ConnectSurfaces(entity1, entity2, network_id)
    -- ensure received data is valid and usable
    if not (entity1 and entity1.valid and entity1.surface and entity1.surface.index and game.surfaces[entity1.surface.index]) then
        if debug_log then tools.log(5, 'ConnectSurfaces', 'Received entity1 was invalid.') end
        return
    end
    if not (entity2 and entity2.valid and entity2.surface and entity2.surface.index and game.surfaces[entity2.surface.index]) then
        if debug_log then tools.log(5, 'ConnectSurfaces', 'Received entity2 was invalid.') end
        return
    end
    if not (network_id and tonumber(network_id, 10)) then
        if debug_log then tools.log(5, 'ConnectSurfaces', 'Received network_id was not a valid integer.') end
        return
    end

    if entity1.surface == entity2.surface then
        if debug_log then tools.log(5, 'ConnectSurfaces', 'Entities [%d] and [%d] are on the same surface %s [%d].', entity1.unit_number, entity2.unit_number, entity1.surface.name, entity1.surface.index) end
        return
    end

    local surface_pair_key = SurfaceInterface.SortedPair(entity1.surface.index, entity2.surface.index)

    storage.ConnectedSurfaces[surface_pair_key] = storage.ConnectedSurfaces[surface_pair_key] or {}
    ---@type table<ltn.EntityPairKey, ltn.SurfaceConnection>
    local surface_connections = storage.ConnectedSurfaces[surface_pair_key]

    local entity_pair_key = SurfaceInterface.SortedPair(entity1.unit_number, entity2.unit_number)

    if debug_log then tools.log(5, 'ConnectSurfaces', 'Creating surface connection between [%d] on %s [%d] and [%d] on %s [%d].', entity1.unit_number, entity1.surface.name, entity1.surface.index, entity2.unit_number, entity2.surface.name, entity2.surface.index) end

    surface_connections[entity_pair_key] = {
        -- enforce a consistent order for repeated calls with the same two entities
        entity1 = entity1.unit_number <= entity2.unit_number and entity1 or entity2,
        entity2 = entity1.unit_number > entity2.unit_number and entity1 or entity2,
        network_id = network_id,
    }
end

--- remove entity references when deleting surfaces
---@param event EventData.on_pre_surface_cleared
function SurfaceInterface.OnSurfaceRemoved(event)
    -- stop references
    local surfaceID = event.surface_index
    tools.log(5, 'OnSurfaceRemoved', 'Removing LTN stops and surface connections on surface [%d].', surfaceID)
    local surface = game.surfaces[surfaceID]
    if surface then
        local train_stops = surface.find_entities_filtered {
            type = 'train-stop'
        }

        for _, entity in pairs(train_stops) do
            if ltn_stop_entity_names[entity.name] then
                RemoveStop(entity.unit_number)
            end
        end
    end

    -- surface connections; surface_index will either be the first half of the key or the second
    local first_surface = '^' .. surfaceID .. '|'
    local second_surface = '|' .. surfaceID .. '$'

    ---@type table<ltn.EntityPairKey, table<ltn.EntityPairKey, ltn.SurfaceConnection>>
    local connected_surfaces = storage.ConnectedSurfaces

    for surface_pair_key, _ in pairs(connected_surfaces) do
        if string.find(surface_pair_key, first_surface) or string.find(surface_pair_key, second_surface) then
            connected_surfaces[surface_pair_key] = nil
        end
    end
end

return SurfaceInterface
