---@meta

---------------------------------------------------------
--- scripts/init.lua
---------------------------------------------------------

--- storage layout
---@class ltn.Storage
---@field tick_state number
---@field tick_interval_start number
---@field tick_stop_index number
---@field messageBuffer any -- TODO
---@field Dispatcher ltn.Dispatcher
---@field LogisticTrainStops table<number, ltn.TrainStop>
---@field ConnectedSurfaces any -- TODO
---@field StoppedTrains table<number, ltn.Train>
---@field StopDistances any -- TODO
---@field WagonCapacity table<string, number>

---@class ltn.Dispatcher
---@field availableTrains table<number, ltn.Train>
---@field availableTrains_total_capacity number
---@field availableTrains_total_fluid_capacity number
---@field Provided table<string, table<number, number>> -- request-type -> stop id -> count
---@field Provided_by_Stop table<number, table<string, number>> -- stop id -> request-type -> count
---@field Requests ltn.Request[]
---@field Requests_by_Stop table<number, table<string, number>>
---@field RequestAge table<string, number>
---@field Deliveries any -- TODO
---@field new_Deliveries any -- TODO

---@class ltn.TrainStop
---@field entity LuaEntity
---@field input LuaEntity
---@field output LuaEntity
---@field lamp_control LuaEntity
---@field active_deliveries number[] -- ?
---@field error_code number
---@field is_depot boolean
---@field depot_priority number
---@field network_id number
---@field min_carriages number
---@field max_carriages number
---@field max_trains number
---@field requesting_threshold number
---@field requesting_threshold_stacks number
---@field requester_priority number
---@field no_warnings boolean
---@field providing_threshold number
---@field providing_threshold_stacks number
---@field provider_priority number
---@field locked_slots number
---@field parked_train_faces_stop boolean?
---@field parked_train LuaTrain?
---@field parked_train_id number?

---@class ltn.Train

---@class ltn.Request
---@field age number
---@field stopID number
---@field priority number
---@field item string
---@field count number


