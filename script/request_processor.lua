----------------------------------------------------------------------------------------
-- Manage request execution and choose train
----------------------------------------------------------------------------------------

local tools = require('script.tools')
local schedule = require('script.schedule')
local SurfaceInterface = require('script.surface-interface')
local Metrics = require('script.metrics')
local RailCache = require('script.cache')

---@class ltn.CandidateProvider
---@field provider ltn.Provider
---@field free_train ltn.FreeTrain
---@field distance ltn.StopDistance?

---@class ltn.TrainCandidate
---@field train LuaTrain
---@field providers table<integer, ltn.CandidateProvider>


---@class ltn.RequestProcessor
local RequestProcessor = {}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

---@param count integer
---@param name string
---@param is_item boolean
---@return integer stack_count
local function compute_stack_size(count, name, is_item)
    return is_item and math.ceil(count / assert(prototypes.item[name]).stack_size) or count
end

---@param request_stop ltn.TrainStop
---@param provider_stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return boolean matches
local function match_stops_by_train_length(request_stop, provider_stop, metrics)
    local match_min = (provider_stop.min_carriages == 0) or (request_stop.max_carriages == 0) or (provider_stop.min_carriages <= request_stop.max_carriages)
    local match_max = (provider_stop.max_carriages == 0) or (request_stop.min_carriages == 0) or (provider_stop.max_carriages >= request_stop.min_carriages)

    if not match_min then metrics:inc('provider_min_too_long') end
    if not match_max then metrics:inc('provider_max_too_short') end

    return match_min and match_max
end

---@param request_stop ltn.TrainStop
---@param provider_stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return boolean matches
local function match_stops_by_force(request_stop, provider_stop, metrics)
    local forces_match = provider_stop.entity.force == request_stop.entity.force
    if not forces_match then metrics:inc('different_force') end
    return forces_match
end

---@param request_stop ltn.TrainStop
---@param provider_stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return integer network_mask
local function match_stops_by_network(request_stop, provider_stop, metrics)
    local network_mask = bit32.band(request_stop.network_id, provider_stop.network_id)
    if network_mask == 0 then metrics:inc('no_matching_network') end
    return network_mask
end

---@param request_stop ltn.TrainStop
---@param provider_stop ltn.TrainStop
---@param network_mask integer
---@param metrics ltn.Metrics
---@return ltn.SurfaceConnection[]?
local function match_stops_by_surface(request_stop, provider_stop, network_mask, metrics)
    if network_mask == 0 then return nil end

    local result = SurfaceInterface.FindSurfaceConnections(request_stop.entity.surface, provider_stop.entity.surface, request_stop.entity.force, network_mask)

    if not result then metrics:inc('different_surface') end

    return result
end

---@param train ltn.Train
---@param stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return boolean
local function train_matches_stop_by_length(train, stop, metrics)
    local min_len_ok = (stop.min_carriages == 0) or (#train.train.carriages >= stop.min_carriages)
    local max_len_ok = (stop.max_carriages == 0) or (#train.train.carriages <= stop.max_carriages)

    if not min_len_ok then metrics:inc('train_too_short') end
    if not max_len_ok then metrics:inc('train_too_long') end

    return min_len_ok and max_len_ok
end

---@param train ltn.Train
---@param stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return boolean
local function train_matches_stop_by_force(train, stop, metrics)
    local forces_match = train.force == stop.entity.force
    if not forces_match then metrics:inc('different_force') end
    return forces_match
end

---@param train ltn.Train
---@param provider ltn.Provider
---@param metrics ltn.Metrics
---@return integer network_mask
local function train_matches_stop_by_network(train, provider, metrics)
    -- provider.network_id is already the requester/provider intersection. The train
    -- must share one of those bits. Matching only the provider stop accepts a depot
    -- that overlaps a different bit of a multi-network provider.
    local network_mask = bit32.band(train.network_id, provider.network_id)
    if network_mask == 0 then metrics:inc('no_matching_network') end
    return network_mask
end

---@param train ltn.Train
---@param stop ltn.TrainStop
---@param network_mask integer
---@param metrics ltn.Metrics
---@return ltn.SurfaceConnection[]?
local function train_matches_stop_by_surface(train, stop, network_mask, metrics)
    if network_mask == 0 then return nil end
    if not train.train.station then return nil end

    local result = SurfaceInterface.FindSurfaceConnections(train.train.station.surface, stop.entity.surface, train.force, network_mask)

    if not result then metrics:inc('different_surface') end

    return result
end

---@param train ltn.Train
---@param locked_slots integer
---@param primary_is_item boolean
---@param metrics ltn.Metrics
---@return integer inventory_size
local function get_train_inventory_size(train, locked_slots, primary_is_item, metrics)
    local item_inventory_size = (train.capacity - (locked_slots * #train.train.cargo_wagons))
    ---@cast item_inventory_size integer
    local fluid_inventory_size = math.floor(train.fluid_capacity)

    if primary_is_item then
        if item_inventory_size == 0 then
            if fluid_inventory_size > 0 then
                metrics:inc('only_fluid_wagons')
            else
                metrics:inc('empty_train')
            end
        end
        return item_inventory_size
    else
        if fluid_inventory_size == 0 then
            if item_inventory_size > 0 then
                metrics:inc('only_cargo_wagons')
            else
                metrics:inc('empty_train')
            end
        end
        return fluid_inventory_size
    end
end

---@param stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return boolean
local function can_accept_train(stop, metrics)
    local activeDeliveryCount = #stop.active_deliveries
    local result = (stop.max_trains == 0) or (activeDeliveryCount == 0) or (activeDeliveryCount < stop.max_trains)

    if not result then metrics:inc('stop_is_full') end

    return result
end

-- return a map of all potential providers for this request
---@param request ltn.Request
---@param request_stop ltn.TrainStop
---@param metrics ltn.Metrics
---@return ltn.Provider[] providers Returns all potential providers sorted by best to worst. All providers *can* serve the request
local function get_providers(request, request_stop, metrics)
    local dispatcher = tools.getDispatcher()

    ---@type ltn.Provider[]
    local providers = {}

    metrics:set('total_count', 0)
    metrics:set('match_count', 0)

    local provider_candidates = dispatcher.Provided[request.item]
    if not provider_candidates then return providers end

    metrics:set('total_count', table_size(provider_candidates))

    for provider_id, available_count in pairs(provider_candidates) do
        local provider_stop = storage.LogisticTrainStops[provider_id]

        -- stop must be valid and match requester force
        if not tools.isStopValid(provider_stop, metrics) then goto continue end
        ---@cast provider_stop -?

        -- network must match
        local matched_networks = match_stops_by_network(request_stop, provider_stop, metrics)
        if matched_networks == 0 then goto continue end

        --  there must be a surface connection
        local surface_connections = match_stops_by_surface(request_stop, provider_stop, matched_networks, metrics)
        if not surface_connections then goto continue end

        if match_stops_by_force(request_stop, provider_stop, metrics)
            -- there must be a compatible set of train length between them
            and match_stops_by_train_length(request_stop, provider_stop, metrics)
            -- the provider must still accept another train
            and can_accept_train(provider_stop, metrics) then
            providers[#providers + 1] = {
                stop = provider_stop,
                network_id = matched_networks,
                priority = provider_stop.provider_priority,
                activeDeliveryCount = #provider_stop.active_deliveries,
                item = request.item,
                count = available_count,
                providing_threshold = provider_stop.providing_threshold,
                providing_threshold_stacks = provider_stop.providing_threshold_stacks,
                min_carriages = provider_stop.min_carriages,
                max_carriages = provider_stop.max_carriages,
                locked_slots = provider_stop.locked_slots,
                surface_connections = surface_connections,
                surface_connections_count = #surface_connections,
            }
        end

        ::continue::
    end

    metrics:set('match_count', table_size(providers))

    table.sort(providers, function(a, b)
        -- sort by priority, will result in train queues if trainlimit is not set
        if a.priority ~= b.priority then
            return a.priority > b.priority
        -- sort providers without surface transition to top
        elseif a.surface_connections_count ~= b.surface_connections_count then
            return math.min(a.surface_connections_count, 1) < math.min(b.surface_connections_count, 1)
        -- sort by #deliveries
        elseif a.activeDeliveryCount ~= b.activeDeliveryCount then
            return a.activeDeliveryCount < b.activeDeliveryCount
        else
            -- finally sort by item count
            return a.count > b.count
        end
    end)

    return providers
end

-- returns: available trains in depots or nil
--          filtered by NetworkID, carriages and surface
---@param provider ltn.Provider
---@param request_stop ltn.TrainStop
---@param primary_is_item boolean
---@param train_metrics ltn.Metrics
---@return table<integer, ltn.FreeTrain>
local function get_free_trains(provider, request_stop, primary_is_item, train_metrics)
    local dispatcher = tools.getDispatcher()

    ---@type table<integer, ltn.FreeTrain>
    local free_trains = {}

    train_metrics:set('total_count', table_size(dispatcher.availableTrains))

    ---@diagnostic disable-next-line: assign-type-mismatch
    train_metrics.trains = {} -- sub-array for per-train metrics for this provider

    for train_id, train_data in pairs(dispatcher.availableTrains) do
        local metrics = Metrics.create()

        if train_data.train.valid then
            if not tools.isStopValid(train_data.train.station, metrics) then goto continue end

            local inventory_size = get_train_inventory_size(train_data, provider.locked_slots, primary_is_item, metrics)
            if inventory_size == 0 then goto continue end

            local matched_networks = train_matches_stop_by_network(train_data, provider, metrics)
            if matched_networks == 0 then goto continue end

            local surface_connections = train_matches_stop_by_surface(train_data, provider.stop, matched_networks, metrics)
            if not (surface_connections and (#surface_connections == 0 or LtnSettings.advanced_cross_surface_delivery)) then goto continue end

            if train_matches_stop_by_force(train_data, provider.stop, metrics)
                and train_matches_stop_by_length(train_data, request_stop, metrics)
                and train_matches_stop_by_length(train_data, provider.stop, metrics) then

                local known_train = tools.getOrCreateKnownTrain(train_data.train)

                free_trains[train_id] = {
                    train = train_data.train,
                    surface = train_data.surface,
                    inventory_size = inventory_size,
                    depot_priority = train_data.depot_priority,
                    surface_connections = surface_connections,
                    select_count = known_train.select_count,
                } --[[@as ltn.FreeTrain ]]
            end
        else
            metrics:inc('train_invalid')

            -- remove invalid train from dispatcher availableTrains
            tools.reduceAvailableCapacity(train_id)
        end

        ::continue::
        if not free_trains[train_id] then
            train_metrics:merge(metrics)
            train_metrics.trains[train_id] = metrics
        end
    end

    return free_trains
end

---@param target_stop LuaEntity
---@param selected_trains ltn.FreeTrain[]
---@param seen_train table<integer, boolean>
---@param free_trains ltn.FreeTrain[]
---@param rail_ends RailEndStart[]
---@param direction defines.rail_direction
---@param all_train_metrics ltn.Metrics
local function compute_path(target_stop, selected_trains, seen_train, free_trains, rail_ends, direction, all_train_metrics)
    while #free_trains > 0 do
        local path_result = game.train_manager.request_train_path {
            type = "path",
            goals = {
                target_stop,
            },
            starts = rail_ends,
        }
        ---@cast path_result TrainPathFinderOneGoalResult
        if path_result.found_path then
            local distance = path_result.penalty and path_result.penalty or path_result.total_length or 0
            ---@cast distance number
            ---@cast path_result.goal_index uint32
            ---@cast path_result.start_index uint32
            local selected_train = assert(free_trains[path_result.start_index])

            local front_distance, back_distance = RailCache.getCachedDistance(selected_train.train, target_stop)
            local stop_distance = (direction == defines.rail_direction.front) and front_distance or back_distance
            RailCache.updateDistance(stop_distance, distance)

            if not selected_train.provider_distance or selected_train.provider_distance > distance then
                selected_train.provider_distance  = distance
            end

            if not seen_train[selected_train.train.id] then
                selected_trains[#selected_trains + 1] = selected_train
                seen_train[selected_train.train.id] = true
            end

            table.remove(rail_ends, path_result.start_index)
            table.remove(free_trains, path_result.start_index)
        else
            -- Mark only the depot/provider pairs in this priority group as unreachable.
            for _, free_train in pairs(free_trains) do
                local depot_stop = free_train.train.station
                ---@cast depot_stop -?

                local front_distance, back_distance = RailCache.getCachedDistance(free_train.train, target_stop)
                local stop_distance = (direction == defines.rail_direction.front) and front_distance or back_distance
                RailCache.updateDistance(stop_distance, DISTANCE_RESULT.UNREACHABLE)
                RailCache.updateUnreachable(free_train.train.id, all_train_metrics, direction)
            end
            free_trains = {}
        end
    end
end

---@param request_stop ltn.TrainStop
---@param primary_is_item boolean
---@param providers ltn.Provider[]
---@param provider_to_train_metrics table<integer, ltn.Metrics>
---@return ltn.Provider? provider
---@return ltn.FreeTrain[] selected_trains
local function select_provider_and_trains(request_stop, primary_is_item, providers, provider_to_train_metrics)
    -- loop through the ordered provider to find one that can be served by a train

    ---@type ltn.FreeTrain[]
    local selected_trains = {}

    for _, provider in pairs(providers) do
        local provider_stop = provider.stop.entity
        local provider_id = provider_stop.unit_number
        ---@cast provider_id -?

        -- find all trains that can serve this provider

        local all_train_metrics = Metrics.create()
        local all_free_trains = get_free_trains(provider, request_stop, primary_is_item, all_train_metrics)
        provider_to_train_metrics[provider_id] = all_train_metrics
        all_train_metrics:set('match_count', 0)

        -- figure out reachability

        ---@type table<string, ltn.PriorityTrainGroup>
        local free_trains_by_priority = {}

        for _, free_train in pairs(all_free_trains) do
            local train = free_train.train
            local depot_stop = train.station
            if depot_stop then -- will be nil if train is moving
                local same_surface = provider_stop.surface_index == depot_stop.surface_index
                local priority = free_train.depot_priority
                local key = tostring(same_surface) .. '-' .. tostring(priority)
                free_trains_by_priority[key] = free_trains_by_priority[key] or {
                    priority = priority,
                    same_surface = same_surface,
                    free_trains = {},
                }
                local priority_group = free_trains_by_priority[key].free_trains
                priority_group[#priority_group + 1] = free_train
            end
        end

        ---@type ltn.PriorityTrainGroup[]
        local priority_train_groups = {}
        for _, value in pairs(free_trains_by_priority) do
            priority_train_groups[#priority_train_groups + 1] = value
        end

        table.sort(priority_train_groups, function(a, b)
            -- prefer trains on the provider surface
            if a.same_surface ~= b.same_surface then return a.same_surface end
            -- prefer higher priority trains over lower priority trains
            return a.priority > b.priority
        end)

        for _, priority_train_group in pairs(priority_train_groups) do
            ---@type RailEndStart[]
            local rail_forwards_starts = {}
            ---@type RailEndStart[]
            local rail_backwards_starts = {}
            ---@type ltn.FreeTrain[]
            local forward_free_trains = {}
            ---@type ltn.FreeTrain[]
            local backward_free_trains = {}

            local cache_metrics = Metrics.create()

            local seen_train = {}
            for _, free_train in pairs(priority_train_group.free_trains) do
                local train = free_train.train

                local front_distance, back_distance = RailCache.getCachedDistance(train, provider_stop)
                if not priority_train_group.same_surface then
                    RailCache.updateDistance(front_distance, DISTANCE_RESULT.OTHER_SURFACE)
                    RailCache.updateDistance(back_distance, DISTANCE_RESULT.OTHER_SURFACE)

                    cache_metrics:inc('other_surface')
                    free_train.provider_distance  = nil
                    if not seen_train[train.id] then
                        selected_trains[#selected_trains + 1] = free_train
                        seen_train[train.id] = true
                    end
                else
                    if #train.locomotives.front_movers > 0 then
                        if RailCache:selectFreeTrain(front_distance, free_train, forward_free_trains, rail_forwards_starts, defines.rail_direction.front, cache_metrics, all_train_metrics) then
                            if not seen_train[train.id] then
                                selected_trains[#selected_trains + 1] = free_train
                                seen_train[train.id] = true
                            end
                        end
                    end
                    if #train.locomotives.back_movers > 0 then
                        if RailCache:selectFreeTrain(back_distance, free_train, backward_free_trains, rail_backwards_starts, defines.rail_direction.back, cache_metrics, all_train_metrics) then
                            if not seen_train[train.id] then
                                selected_trains[#selected_trains + 1] = free_train
                                seen_train[train.id] = true
                            end
                        end
                    end
                end
            end

            local metrics_result = cache_metrics:summarize({ '', }, 'CACHE_METRICS')

            if table_size(cache_metrics) > 0 then
                local force = request_stop.entity.force

                tools.printmsg(3, function()
                    local request_network_id = request_stop.network_id
                    local to = request_stop.entity.backer_name
                    local to_gps = tools.richTextForStop(request_stop.entity) or to
                    local to_network_ids, to_network_id_count = tools.networkList(request_network_id)

                    return { 'ltn-message.cache-metrics', to_gps, { 'ltn-message.network', to_network_id_count, to_network_ids }, metrics_result } --[[@as LocalisedString]]
                end, force)
            end

            if #forward_free_trains > 0 then
                compute_path(provider_stop, selected_trains, seen_train, forward_free_trains, rail_forwards_starts, defines.rail_direction.front, all_train_metrics)
            end
            if #backward_free_trains > 0 then
                compute_path(provider_stop, selected_trains, seen_train, backward_free_trains, rail_backwards_starts, defines.rail_direction.back, all_train_metrics)
            end

            -- at least one train in the priority group is available
            if #selected_trains > 0 then
                all_train_metrics:set('match_count', #selected_trains)
                return provider, selected_trains
            end
        end
    end

    return nil, {}
end

-- Selects a train for the delivery
---@param free_trains ltn.FreeTrain[]?
---@param provider_surface_index integer
---@param stacks integer
---@return ltn.FreeTrain?
local function select_train(free_trains, provider_surface_index, stacks)
    if not free_trains or #free_trains < 1 then return nil end

    local fudge_factor = LtnSettings.depot_fudge_factor or 0

    table.sort(free_trains, function(a, b)
        -- if A is on the same surface as the stop and B is not, return true
        if a.surface.index == provider_surface_index and b.surface.index ~= provider_surface_index then
            return true
            -- if B is on the same surface as the stop and A is not, return false
        elseif b.surface.index == provider_surface_index and a.surface.index ~= provider_surface_index then
            return false
            -- else do normal checks (either both stops are on the same or on a different surface)
        elseif a.depot_priority ~= b.depot_priority then
            --sort by priority
            return a.depot_priority > b.depot_priority
        elseif a.inventory_size ~= b.inventory_size and a.inventory_size >= stacks then
            --sort inventories capable of whole deliveries
            -- return not(b.inventory_size => size and a.inventory_size > b.inventory_size)
            return b.inventory_size < stacks or a.inventory_size < b.inventory_size
        elseif a.inventory_size ~= b.inventory_size and a.inventory_size < stacks then
            --sort inventories for partial deliveries
            -- return not(b.inventory_size >= size or b.inventory_size > a.inventory_size)
            return b.inventory_size < stacks and b.inventory_size < a.inventory_size
        else
            -- if one stop is on the same surface and the other is not, return
            if not a.provider_distance or a.provider_distance <= 0 then return false end
            if not b.provider_distance or b.provider_distance <= 0 then return true end

            if math.abs(a.provider_distance - b.provider_distance) > fudge_factor then
                return a.provider_distance < b.provider_distance
            end

            return a.select_count < b.select_count
        end
    end)

    return free_trains[1]
end

---@param train_capacity integer Either stacks (item) or total capacity (fluid)
---@param loading_element ltn.ItemLoadingElement
---@return ltn.ItemLoadingElement loading_element
local function limit_to_train_capacity(train_capacity, loading_element)
    if loading_element.item.type == 'fluid' then
        -- fluids have the same count and stacks
        loading_element.count = math.min(loading_element.count, train_capacity)
        loading_element.stacks = loading_element.count
    else
        -- clamp the delivery to the actually available capacity on the train
        loading_element.stacks = math.min(loading_element.stacks, train_capacity)
        loading_element.count = math.min(loading_element.count, loading_element.stacks * assert(prototypes.item[loading_element.item.name]).stack_size)
    end

    return loading_element
end

--- If the primary item did not fill the full train, opportunistically look for additional deliveries
--- that can be squeezed in the train.
---@param loading_list ltn.ItemLoadingElement[]
---@param free_train ltn.FreeTrain
---@param provider ltn.Provider
---@param request ltn.Request
---@return integer total_stacks
local function create_merged_delivery(loading_list, free_train, provider, request)
    if #loading_list < 1 then return 0 end
 local stacks_available = free_train.inventory_size - loading_list[1].stacks

    local dispatcher = tools.getDispatcher()
    local provider_id = provider.stop.entity.unit_number
    ---@cast provider_id -?

    -- temporary remove the request in the dispatcher, otherwise the primary
    -- will be picked up as a potential merge item
    local dispatched_request = dispatcher.Requests_by_Stop[request.stopID]
    ---@cast dispatched_request -?
    local primary_request_count = dispatched_request[request.item]
    dispatched_request[request.item] = nil

    for merge_item, merge_request_count in pairs(dispatched_request) do
        if stacks_available <= 0 then break end

        local merge_item_info = tools.parseItemIdentifier(merge_item)
        if merge_item_info and merge_item_info.type == 'item' then
            local merge_item_prototype = assert(prototypes.item[merge_item_info.name])
            local merge_localname = merge_item_prototype.localised_name
            -- get current provider for requested item
            if dispatcher.Provided[merge_item] and dispatcher.Provided[merge_item][provider_id] then
                -- smaller of provider and requester is the amount that can be transferred.
                local merge_delivery_size = math.min(dispatcher.Provided[merge_item][provider_id], merge_request_count)
                local merge_stacks = math.ceil(merge_delivery_size / merge_item_prototype.stack_size)

                local loading_element = limit_to_train_capacity(stacks_available, {
                    item = merge_item_info,
                    localname = merge_localname,
                    count = merge_delivery_size,
                    stacks = merge_stacks
                })

                -- add to loading list
                loading_list[#loading_list + 1] = loading_element
                stacks_available = stacks_available - loading_element.stacks

                tools.log(5, 'create_merged_delivery', 'inserted into order %s >> %s: %d %s in %d/%d stacks.', function()
                    local to = assert(storage.LogisticTrainStops[request.stopID])
                    return provider.stop.entity.backer_name, to.entity.backer_name, loading_element.count, merge_item, loading_element.stacks,
                        free_train.inventory_size
                end)
            end
        end
    end

    dispatched_request[request.item] = primary_request_count

    return free_train.inventory_size - stacks_available
end

-- Update dispatcher state based on a given loading element.
---@param loading_element ltn.ItemLoadingElement
---@param provider ltn.Provider
---@param to_id integer
---@return string loading_element_id
local function update_dispatcher_provided(loading_element, provider, to_id)
    local dispatcher = tools.getDispatcher()

    local loading_element_id = tools.createItemIdentifier(loading_element.item)
    local from_id = assert(provider.stop.entity.unit_number)

    local provided = dispatcher.Provided[loading_element_id]
    ---@cast provided -?

    -- subtract Delivery from Provided items and check thresholds
    provided[from_id] = assert(provided[from_id]) - loading_element.count

    local use_stack_threshold = false
    local provided_stacks = 0
    if loading_element.item.type == 'item' then
        provided_stacks = math.floor(provided[from_id] / assert(prototypes.item[loading_element.item.name]).stack_size)
        use_stack_threshold = provider.providing_threshold_stacks > 0
    end

    local provided_by_stop = assert(dispatcher.Provided_by_Stop[from_id])
    if (use_stack_threshold and provided_stacks >= provider.providing_threshold_stacks) or
        (not use_stack_threshold and provided[from_id] >= provider.providing_threshold) then
        provided_by_stop[loading_element_id] = provided[from_id]
    else
        provided[from_id] = nil
        provided_by_stop[loading_element_id] = nil
    end

    -- remove Request and reset age
    local requests_by_stop = assert(dispatcher.Requests_by_Stop[to_id])
    requests_by_stop[loading_element_id] = nil
    dispatcher.RequestAge[loading_element_id .. ',' .. to_id] = nil

    tools.log(5, 'update_dispatcher_provided', '  %s, %d in %d stacks', function()
        return loading_element_id, loading_element.count, loading_element.stacks
    end)

    local pending_requests = assert(dispatcher.Pending_Requests[to_id])
    -- update pending requests so that Dispatcher Update API call is correct
    local pending_amount = pending_requests[loading_element_id]
    if pending_amount then
        pending_amount = pending_amount - loading_element.count
        pending_requests[loading_element_id] = (pending_amount > 0) and pending_amount or nil
    end

    return loading_element_id
end

-- Create the schedule for the train
---@param train LuaTrain
---@param loading_list ltn.ItemLoadingElement[]
---@param provider_stop ltn.TrainStop
---@param request_stop ltn.TrainStop
---@return ltn.TrainStop depot
local function create_train_schedule(train, loading_list, provider_stop, request_stop)

    ---@cast train.station -?
    local depot = assert(storage.LogisticTrainStops[train.station.unit_number])

    schedule:resetSchedule(train, depot)

    -- rail entities have been validated with IsValidStop before
    local from_rail = assert(provider_stop.entity.connected_rail)
    local from_rail_direction = provider_stop.entity.connected_rail_direction
    local to_rail = assert(request_stop.entity.connected_rail)
    local to_rail_direction = request_stop.entity.connected_rail_direction
    local current_train_surface = depot.entity.surface

    -- make train go to specific stations by setting a temporary waypoint on the rail the station is connected to
    --
    -- schedules cannot have temporary stops on a different surface, those need to be added when the delivery is updated with a train on a different surface
    if current_train_surface == from_rail.surface then
        schedule:temporaryStop(train, from_rail, from_rail_direction)
    else
        tools.log(5, 'create_train_schedule', ' Warning: creating schedule without temporary stop for provider.')
    end

    schedule:providerStop(train, provider_stop, loading_list)

    if (current_train_surface == to_rail.surface) and (to_rail.surface == from_rail.surface) then
        schedule:temporaryStop(train, to_rail, to_rail_direction)
    else
        tools.log(5, 'create_train_schedule', ' Warning: creating schedule without temporary stop for requester.')
    end

    schedule:requesterStop(train, request_stop, loading_list)

    return depot
end

-- parse single request from dispatcher Request={stopID, item, age, count}
-- returns created delivery ID or nil
---@param reqIndex integer
---@param request ltn.Request
---@return number?
function RequestProcessor.processRequest(reqIndex, request)
    local to_id = request.stopID

    -- ensure validity of request stop
    local request_stop = storage.LogisticTrainStops[to_id]
    if not tools.isStopValid(request_stop) then return nil end
    ---@cast request_stop -?

    local request_network_id = request_stop.network_id
    local to = request_stop.entity.backer_name
    local to_gps = tools.richTextForStop(request_stop.entity) or to
    local to_network_ids, to_network_id_count = tools.networkList(request_network_id)
    local force = request_stop.entity.force

    local dispatcher = tools.getDispatcher()

    tools.log(5, 'RequestProcessor:processRequest', 'request %d/%d: %d(%d) %s to %s {%s} priority: %d min length: %d max length: %d', function()
        return reqIndex, #dispatcher.Requests, request.count, request_stop.requesting_threshold, request.item, to, to_network_ids, request.priority,
            request_stop.min_carriages, request_stop.max_carriages
    end)

    -- Skip request, item has already been processed
    if not (dispatcher.Requests_by_Stop[to_id] and dispatcher.Requests_by_Stop[to_id][request.item]) then return nil end

        -- Reached limit for request station
    if request_stop.max_trains > 0 and #request_stop.active_deliveries >= request_stop.max_trains then return nil end

    local item_info = tools.parseItemIdentifier(request.item)
    if not item_info then
        tools.printmsg(1, function() return { 'ltn-message.error-parse-item', request.item } end, force)
        tools.log(5, 'RequestProcessor:processRequest', ' could not parse %s', function() return request.item end)
        return nil
    end

    ---@cast item_info.name -?
    ---@cast item_info.type -?
    local primary_is_item = (item_info.type == 'item')

    -- quick check if any trains are available
    local capacity = primary_is_item
        and (dispatcher.availableTrains_total_capacity or 0)
        or (dispatcher.availableTrains_total_fluid_capacity or 0)

    if capacity == 0 then
        create_alert(request_stop.entity, 'depot-empty', { primary_is_item and 'ltn-message.empty-depot-item' or 'ltn-message.empty-depot-fluid' }, force)

        tools.printmsg(1, function()
            return { primary_is_item and 'ltn-message.empty-depot-item' or 'ltn-message.empty-depot-fluid' }
        end, force)

        -- no train available, bail out.
        ---@type ltn.EventData.no_train_found_item
        local data = {
            to = to,
            to_id = to_id,
            network_id = request_network_id,
            item = request.item
        }

        script.raise_event(on_dispatcher_no_train_found_event, data)
        return nil
    end

    -- 1) Find all eligible providers

    local provider_metrics = Metrics.create()
    local providers = get_providers(request, request_stop, provider_metrics)

    ---@type table<integer, ltn.Metrics>
    local provider_to_train_metrics = {}

    -- 2) select a provider and matching trains for it
    local provider, selected_trains = select_provider_and_trains(request_stop, primary_is_item, providers, provider_to_train_metrics)

    provider_metrics:set('match_count', provider and 1 or 0)

    if not provider then
        -- can only happen if no provider has a matching train
        if not request_stop.no_warnings then
            for _, provider_to_train_metric in pairs(provider_to_train_metrics) do
                if provider_to_train_metric:get('match_count') == 0 then provider_metrics:inc('no_train_available') end
            end

            local total_count = provider_metrics:get('total_count')
            local msg = (total_count == 0) and 'ltn-message.no-provider-found' or 'ltn-message.no-provider-available'
            local metrics_result = provider_metrics:summarize({ '', }, 'PROCESS_REQUEST_METRICS')

            tools.printmsg(1, function()
                return { msg, to_gps, tools.prettyPrint(item_info), { 'ltn-message.network', to_network_id_count, to_network_ids }, metrics_result, total_count } --[[@as LocalisedString ]]
            end, force)
        end

        return nil
    end


    -- 3) We found a provider with trains. Choose the best train

    local provider_stop = provider.stop

    local from_id = assert(provider_stop.entity.unit_number)
    local from = provider_stop.entity.backer_name
    local from_gps = tools.richTextForStop(provider_stop.entity) or from

    local matched_network_ids, matched_network_count = tools.networkList(bit32.band(provider.network_id, request_network_id))
    local matched_network_id_str = { 'ltn-message.network', matched_network_count, matched_network_ids }

    local min_carriages = math.max(request_stop.min_carriages, provider_stop.min_carriages)
    local max_carriages = math.min(request_stop.max_carriages, provider_stop.max_carriages)

    tools.printmsg(3, function()
        return { 'ltn-message.provider-found',
            from_gps, tostring(provider.priority), tostring(provider.activeDeliveryCount), provider.count, tools.prettyPrint(item_info) } --[[@as LocalisedString ]]
    end, force)

    -- limit delivery_size to minimum between provider and requester
    local delivery_size = math.min(request.count, provider.count)
    local stacks = math.ceil(compute_stack_size(delivery_size, item_info.name, primary_is_item))

    -- this represents the final loading list for the train. It may contain only a single thing or there may be
    -- more things added for merged deliveries. This is also not yet the final size as the train may be too small
    -- to accommodate all of the requested items.

    ---@type ltn.ItemLoadingElement[]
    local loading_list = {
        {
            item = item_info,
            localname = assert(prototypes[item_info.type][item_info.name]).localised_name,
            count = delivery_size,
            stacks = stacks
        }
    }

    local free_train = select_train(selected_trains, provider_stop.entity.surface_index, stacks)
    if not free_train then
        create_alert(request_stop.entity,
            'depot-empty', {
                'ltn-message.no-train-found',
                from, to, matched_network_id_str, tostring(min_carriages), tostring(max_carriages)
            }  --[[@as LocalisedString]],
            force)

        tools.printmsg(1, function()
            return { 'ltn-message.no-train-found', from_gps, to_gps, matched_network_id_str, tostring(min_carriages), tostring(max_carriages) }  --[[@as LocalisedString]]
        end, force)

        ---@type ltn.EventData.no_train_found_shipment
        local data = {
            to = to,
            to_id = to_id,
            from = from,
            from_id = from_id,
            network_id = request_network_id,
            min_carriages = min_carriages,
            max_carriages = max_carriages,
            shipment = tools.createLoadingList(loading_list),
        }

        script.raise_event(on_dispatcher_no_train_found_event, data)

        return nil
    end

    local train = free_train.train

    -- 4) deduplicate surface connections

    local known_connections = {}
    local surface_connections = {}
    -- surface connections can come from the train itself or the provider stop
    for _, connection_source in pairs { provider.surface_connections, free_train.surface_connections } do
        for _, surface_connection in pairs(connection_source) do
            local entity_key = tools.sortedPair(surface_connection.entity1.unit_number, surface_connection.entity2.unit_number)
            if not known_connections[entity_key] then
                known_connections[entity_key] = surface_connection
                surface_connections[#surface_connections + 1] = surface_connection
            end
        end
    end

    provider.surface_connections = surface_connections
    provider.surface_connections_count = #surface_connections

    -- 5) create load list, merge deliveries if possible

    -- fix the loading list, now that we know the train size
    loading_list = { limit_to_train_capacity(free_train.inventory_size, assert(loading_list[1])) }

    ---@type LocalisedString
    local total_stacks_str = primary_is_item
        and { 'ltn-message.stack', create_merged_delivery(loading_list, free_train, provider, request) }
        or { '', tostring(loading_list[1].stacks) }

    tools.printmsg(3, function()
        return { 'ltn-message.train-found', from_gps, to_gps, matched_network_id_str, tostring(free_train.inventory_size), total_stacks_str }  --[[@as LocalisedString]]
    end, force)

    tools.printmsg(2, function()
        if #loading_list == 1 then
            return { 'ltn-message.creating-delivery', from_gps, to_gps, tools.richTextForTrain(train), tools.printLoadingList(loading_list),
                matched_network_id_str }  --[[@as LocalisedString]]
        else
            return { 'ltn-message.creating-delivery-merged', from_gps, to_gps, tools.richTextForTrain(train), tools.printLoadingList(loading_list),
                matched_network_id_str, total_stacks_str }  --[[@as LocalisedString]]
        end
    end, force)

    -- 6) housekeeping the internal state for the delivery

    ---@type table<string, integer>
    local shipment = {}

    for _, loading_element in pairs(loading_list) do
        local loading_element_id = update_dispatcher_provided(loading_element, provider, to_id)
        shipment[loading_element_id] = loading_element.count
    end

    -- 7) Create schedule for train

    local depot_stop = create_train_schedule(train, loading_list, provider_stop, request_stop)

    -- increase select count for the train, now that it has a schedule
    local known_train = tools.getOrCreateKnownTrain(train)
    known_train.select_count = known_train.select_count + 1

    dispatcher.new_Deliveries[#dispatcher.new_Deliveries + 1] = train.id

    dispatcher.Deliveries[train.id] = {
        force = force,
        train = train,
        from = from or '',
        from_id = from_id,
        to = to or '',
        to_id = to_id,
        network_id = provider.network_id,
        started = game.tick,
        surface_connections = provider.surface_connections,
        shipment = shipment,
    }

    tools.reduceAvailableCapacity(train.id)

    -- 8) Update the various stops

    -- train is no longer available => set depot to yellow
    setLamp(depot_stop, 'yellow', 1)

    -- update delivery count and lamps on provider and requester
    for _, stop_id in pairs { from_id, to_id } do
        -- update the delivery count in the mod storage
        local stop = assert(storage.LogisticTrainStops[stop_id])
        stop.active_deliveries[#stop.active_deliveries + 1] = train.id

        local current_signal = getLamp(stop)
        -- only update blue signal count; change to yellow if it wasn't blue
        local color = (current_signal and current_signal.value and current_signal.value.name == 'signal-blue') and 'blue' or 'yellow'
        setLamp(stop, color, #stop.active_deliveries)
    end

    return train.id -- deliveries are indexed by train.id
end

return RequestProcessor
