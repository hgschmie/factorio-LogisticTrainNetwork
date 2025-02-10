---@meta

---------------------------------------------------------
--- LTN data types
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


---------------------------------------------------------
--- Type aliases
---------------------------------------------------------

--- A shipment, consisting of comma-separated description strings and an amount.
---@alias ltn.Shipment table<string, number>

---@alias ltn.LoadingList ltn.LoadingElement[]

---------------------------------------------------------
--- Main types
---------------------------------------------------------

--- The event dispatcher.
---@class ltn.Dispatcher
---@field availableTrains table<number, ltn.Train>
---@field availableTrains_total_capacity number
---@field availableTrains_total_fluid_capacity number
---@field Provided table<string, table<number, number>> -- request-type -> stop id -> count
---@field Provided_by_Stop table<number, ltn.Shipment> -- stop id -> request-type -> count
---@field Requests ltn.Request[]
---@field Requests_by_Stop table<number, ltn.Shipment>
---@field RequestAge table<string, number>
---@field Deliveries table<number, ltn.Delivery>
---@field new_Deliveries table<number, ltn.Delivery>

--- LTN stop information
---@class ltn.TrainStop
---@field active_deliveries number[]            List of train ids that are either requesting or providing to this stop
---@field entity LuaEntity                      The Train stop entity itself
---@field input LuaEntity                       The Lamp entity (input) of the Train stop
---@field output LuaEntity                      The combinator entity (output) of the Train stop
---@field lamp_control LuaEntity                Hidden combinator that controls the input lamp
---@field error_code number                     Current error state of the stop
---@field is_depot boolean                      True if the stop is a depot
---@field depot_priority number                 Depot priority value
---@field network_id number                     Encoded network id for the stop
---@field min_carriages number                  minimum train length for this stop
---@field max_carriages number                  maximum train length for this stop
---@field max_trains number                     maximum number of trains allowed to this stop
---@field providing_threshold number            Provider threshold value (items and fluids)
---@field providing_threshold_stacks number     Provider stack threshold value (for items only)
---@field provider_priority number              Provider priority value
---@field requesting_threshold number           Requester threshold value (items and fluids)
---@field requesting_threshold_stacks number    Requester stack threshold value (for items only)
---@field requester_priority number             Requester priority value
---@field locked_slots number                   Locked slots per wagon for this stop
---@field no_warnings boolean                   If true, warnings are disabled for this stop
---@field parked_train LuaTrain?                The currently parked train at this stop
---@field parked_train_id number?               The train id of the currently parked train
---@field parked_train_faces_stop boolean?      True if the train faces the stop, false otherwise

--- LTN Train information
---@class ltn.Train
---@field capacity       number
---@field fluid_capacity number
---@field force          LuaForce
---@field surface        LuaSurface
---@field depot_priority number
---@field network_id     number
---@field train          LuaTrain

--- A request for a shipment.
---@class ltn.Request
---@field age      number
---@field stopID   number
---@field priority number
---@field item     string
---@field count    number

--- A scheduled delivery
---@class ltn.Delivery
---@field force LuaForce
---@field train LuaTrain
---@field from string
---@field from_id number
---@field to string
---@field to_id number
---@field network_id number
---@field started number
---@field surface_connections ltn.SurfaceConnection[]
---@field shipment ltn.Shipment

---@class ltn.SurfaceConnection

---------------------------------------------------------
--- Event payloads
---------------------------------------------------------

---@class ltn.EventData.on_stops_updated
---@field logistic_train_stops table<number, ltn.TrainStop> All train stops known to LTN

---@class ltn.EventData.on_dispatcher_updated
---@field update_interval  number time in ticks LTN needed to run all updates, varies depending on number of stops and requests
---@field provided_by_stop table<number, ltn.Shipment>
---@field requests_by_stop table<number, ltn.Shipment>
---@field new_deliveries   table<number, ltn.Delivery>
---@field deliveries       table<number, ltn.Delivery>
---@field available_trains table<number, ltn.Train>

---@class ltn.LoadingElement
---@field type string comma string?
---@field name string ItemName
---@field localname string ??
---@field count number
---@field stacks number

---@class ltn.EventData.no_train_found_item
---@field to            string? Target stop
---@field to_id         number  Target stop id
---@field network_id    number  Network id
---@field item          string? The item to deliver

---@class ltn.EventData.no_train_found_shipment
---@field from          string? Source stop
---@field from_id       number? Source stop id
---@field to            string? Target stop
---@field to_id         number  Target stop id
---@field network_id    number  Network id
---@field min_carriages number? Minimum train length
---@field max_carriages number? Maximum train length
---@field shipment      ltn.LoadingList? The loading list to deliver

---@alias ltn.EventData.no_train_found (ltn.EventData.no_train_found_item|ltn.EventData.no_train_found_shipment)

---@class ltn.EventData.delivery_pickup_complete
---@field train LuaTrain
---@field train_id number
---@field planned_shipment ltn.Shipment
---@field actual_shipment ltn.Shipment

---@class ltn.EventData.delivery_complete
---@field train LuaTrain
---@field train_id number
---@field shipment ltn.Shipment

---@class ltn.EventData.on_delivery_failed
---@field train_id number                       The Train Id that failed the delivery
---@field shipment ltn.Shipment                 The failed shipment

---@class ltn.EventData.provider_missing_cargo
---@field train LuaTrain
---@field station LuaEntity
---@field planned_shipment ltn.Shipment
---@field actual_shipment ltn.Shipment

---@class ltn.EventData.unscheduled_cargo
---@field train LuaTrain
---@field station LuaEntity
---@field planned_shipment ltn.Shipment
---@field unscheduled_load ltn.Shipment

---@class ltn.EventData.requester_remaining_cargo
---@field train LuaTrain
---@field station LuaEntity
---@field remaining_load ltn.Shipment
