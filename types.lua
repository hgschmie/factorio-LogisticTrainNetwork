---@meta

---------------------------------------------------------
--- LTN data types
---------------------------------------------------------

--- storage layout
---@class ltn.Storage
---@field tick_state            number
---@field tick_interval_start   number
---@field tick_stop_index       number?
---@field Dispatcher            ltn.Dispatcher
---@field LogisticTrainStops    table<integer, ltn.TrainStop>
---@field ConnectedSurfaces     table<ltn.EntityPairKey, table<ltn.EntityPairKey, ltn.SurfaceConnection>>
---@field StoppedTrains         table<number, ltn.StoppedTrain>
---@field StopDistances         table<string, number>
---@field WagonCapacity         table<string, number>
---@field FuelStations          ltn.TrainStop[][]
---@field Depots                ltn.TrainStop[][]

---------------------------------------------------------
--- Type aliases
---------------------------------------------------------

--- A shipment, consisting of comma-separated description strings and an amount.
---@alias ltn.Shipment table<ltn.ItemIdentifier, number>

--- typed string for the item identifiers
---@alias ltn.ItemIdentifier string

--- typed string for surface connection identifier
---@alias ltn.EntityPairKey string

---@alias ltn.LoadingList ltn.LoadingElement[]

---@alias ltn.AlertType ('cargo-warning'|'cargo-alert'|'deport-warning'|'depot-empty')

---@alias ltn.ItemFluid ('item'|'fluid')

---@alias ltn.InventoryType table<string, ItemWithQualityCount>
---@alias ltn.FluidInventoryType table<string, number>

---------------------------------------------------------
--- Main types
---------------------------------------------------------

--- The event dispatcher.
---@class ltn.Dispatcher
---@field availableTrains                      table<number, ltn.Train>
---@field availableTrains_total_capacity       number
---@field availableTrains_total_fluid_capacity number
---@field Provided                             table<ltn.ItemIdentifier, table<number, number>> -- request-type -> stop id -> count
---@field Provided_by_Stop                     table<number, ltn.Shipment> -- stop id -> request-type -> count
---@field Requests                             ltn.Request[]
---@field Requests_by_Stop                     table<number, ltn.Shipment>
---@field RequestAge                           table<string, number>
---@field Deliveries                           table<number, ltn.Delivery>
---@field new_Deliveries                       number[]

--- LTN stop information
---@class ltn.TrainStop
---@field active_deliveries           number[]   List of train ids that are either requesting or providing to this stop
---@field entity                      LuaEntity  The Train stop entity itself
---@field input                       LuaEntity  The Lamp entity (input) of the Train stop
---@field output                      LuaEntity  The combinator entity (output) of the Train stop
---@field lamp_control                LuaEntity  Hidden combinator that controls the input lamp
---@field error_code                  number     Current error state of the stop
---@field is_depot                    boolean    True if the stop is a depot
---@field is_fuel_station             boolean    True if the stop is a fuel station
---@field depot_priority              number     Depot priority value
---@field network_id                  number     Encoded network id for the stop
---@field min_carriages               number     minimum train length for this stop
---@field max_carriages               number     maximum train length for this stop
---@field max_trains                  number     maximum number of trains allowed to this stop
---@field providing_threshold         number     Provider threshold value (items and fluids)
---@field providing_threshold_stacks  number     Provider stack threshold value (for items only)
---@field provider_priority           number     Provider priority value
---@field requesting_threshold        number     Requester threshold value (items and fluids)
---@field requesting_threshold_stacks number     Requester stack threshold value (for items only)
---@field requester_priority          number     Requester priority value
---@field locked_slots                number     Locked slots per wagon for this stop
---@field no_warnings                 boolean    If true, warnings are disabled for this stop
---@field parked_train                LuaTrain?  The currently parked train at this stop
---@field parked_train_id             number?    The train id of the currently parked train
---@field parked_train_faces_stop     boolean?   True if the train faces the stop, false otherwise
---@field fuel_signals                (CircuitCondition[])? Fuel Signals for a fuel station, used to create refuel interrupt condition

--- LTN Train information
---@class ltn.Train
---@field train             LuaTrain
---@field force             LuaForce
---@field capacity          number
---@field fluid_capacity    number
---@field surface           LuaSurface
---@field depot_priority    number
---@field network_id        number

--- LTN Train information
---@class ltn.StoppedTrain
---@field train             LuaTrain
---@field name              string?
---@field force             LuaForce?
---@field stopID            number

--- A request for a shipment.
---@class ltn.Request
---@field age               number
---@field stopID            number
---@field priority          number
---@field item              ltn.ItemIdentifier
---@field count             number

--- A scheduled delivery
---@class ltn.Delivery
---@field force                LuaForce
---@field train                LuaTrain
---@field from                 string
---@field from_id              number
---@field to                   string
---@field to_id                number
---@field network_id           number
---@field started              number
---@field surface_connections  ltn.SurfaceConnection[]
---@field shipment             ltn.Shipment
---@field pickupDone           boolean?

---@class ltn.LoadingElement
---@field type             ltn.ItemFluid 'item' or 'fluid'
---@field name             string  Item or fluid name
---@field quality          string? *Since 2.1.0* Requested quality. If missing, 'normal' quality was requested
---@field localname        string  Localized name
---@field count            number  number of elements
---@field stacks           number  stack size for items


---@class ltn.SurfaceConnection
---@field entity1    LuaEntity
---@field entity2    LuaEntity
---@field network_id number

---------------------------------------------------------
--- Internal types used in various methods
---------------------------------------------------------

---@class ltn.Provider
---@field stop                        ltn.TrainStop
---@field network_id                  number
---@field priority                    number
---@field activeDeliveryCount         number
---@field item                        ltn.ItemIdentifier
---@field count                       number
---@field providing_threshold         number
---@field providing_threshold_stacks  number
---@field min_carriages               number
---@field max_carriages               number
---@field locked_slots                number
---@field surface_connections         ltn.SurfaceConnection[]
---@field surface_connections_count   number

---@class ltn.FreeTrain
---@field train             LuaTrain
---@field inventory_size    number
---@field depot_priority    number
---@field provider_distance number

---@class ltn.ItemLoadingElement
---@field item      SignalID
---@field localname string  Localized name
---@field count     number  number of elements
---@field stacks    number  stack size for items

---@class ltn.SignalState
---@field is_depot boolean
---@field is_fuel_station boolean
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

---------------------------------------------------------
--- Event payloads
---------------------------------------------------------

---@class ltn.EventData.on_stops_updated
---@field logistic_train_stops  table<number, ltn.TrainStop> All train stops known to LTN

---@class ltn.EventData.on_dispatcher_updated
---@field update_interval       number time in ticks LTN needed to run all updates, varies depending on number of stops and requests
---@field provided_by_stop      table<number, ltn.Shipment>
---@field requests_by_stop      table<number, ltn.Shipment>
---@field new_deliveries        number[]
---@field deliveries            table<number, ltn.Delivery>
---@field available_trains      table<number, ltn.Train>

---@alias ltn.EventData.no_train_found (ltn.EventData.no_train_found_item|ltn.EventData.no_train_found_shipment)

---@class ltn.EventData.no_train_found_item
---@field to               string? Target stop
---@field to_id            number  Target stop id
---@field network_id       number  Network id
---@field item             ltn.ItemIdentifier? The item to deliver

---@class ltn.EventData.no_train_found_shipment
---@field from             string?          Source stop
---@field from_id          number?          Source stop id
---@field to               string?          Target stop
---@field to_id            number           Target stop id
---@field network_id       number           Network id
---@field min_carriages    number?          Minimum train length
---@field max_carriages    number?          Maximum train length
---@field shipment         ltn.LoadingList? The loading list to deliver

---@class ltn.EventData.delivery_pickup_complete
---@field train            LuaTrain
---@field train_id         number
---@field planned_shipment ltn.Shipment
---@field actual_shipment  ltn.Shipment

---@class ltn.EventData.delivery_complete
---@field train            LuaTrain
---@field train_id         number
---@field shipment         ltn.Shipment

---@class ltn.EventData.on_delivery_failed
---@field train_id         number        The Train Id that failed the delivery
---@field shipment         ltn.Shipment  The failed shipment

---@class ltn.EventData.provider_missing_cargo
---@field train            LuaTrain
---@field station          LuaEntity
---@field planned_shipment ltn.Shipment
---@field actual_shipment  ltn.Shipment

---@class ltn.EventData.unscheduled_cargo
---@field train             LuaTrain
---@field station           LuaEntity
---@field planned_shipment  ltn.Shipment
---@field unscheduled_load  ltn.Shipment

---@class ltn.EventData.requester_remaining_cargo
---@field train           LuaTrain
---@field station         LuaEntity
---@field remaining_load  ltn.Shipment
