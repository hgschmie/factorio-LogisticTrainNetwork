# Additional documentation and manual

## Station colors

* Green - Normal Operation
* Yellow - Pending delivery operation. Station is either a requester or a provider.
* Blue - Train is parked at the stop.
* White - Station is not initialized.
* Red - Station is in an error state.
* Cyan - Station is a refuel station.

All station colors can be read on the circuit network by connecting a green wire to the station lamp:

* Virtual Signal "green" - 1 - Normal Operation
* Virtual Signal "yellow" - n - Pending delivery operation. n is the number of trains using this stop.
* Virtual Signal "blue" - n - Train parked at the stop. n is the number of trains
* Virtual Signal "white" - Train stop is not initialized (error)
* Virtual Signal "red" - 1 - "short circuit", input (lamp), output (combinator) or the train stop connector are connected to each other
* Virtual Signal "red" - 2 - "disabled". The train stop has been disabled (e.g., through a circuit condition).
* Virtual Signal "cyan" - Train stop is a refuel station.

When using a single combinator for multiple stations (e.g., for a depot), the combinator should connect to the train stop inputs (lamps) using the *red* wire connection. This ensures that the different station lamps function correctly. When using a green wire, the virtual signals will be connected across the stops and the lamps will not show the correct state. The stations will continue to function correctly, only the lamp color will be incorrect.

## Metrics

When creating a delivery, it is possible that LTN could not select a provider, even though some providers exist that should have been able to provide items or fluids. LTN prints a summary on why it could not select existing providers:

* `Network mismatch` - There is no shared LTN network between the provider and the requester.
* `No train available` - There is no train available to fulfil the delivery between a selected provider and the requester.
* `Only fluid wagons` - A delivery has items and a selected train has only fluid wagons.
* `Only cargo wagons` - A delivery has fluids and a selected train has only cargo wagons.
* `Stop is full` - The maximum number of trains defined by the provider train limit has been reached.
* `Stop is unreachable` - The game could not find any path from a depot to the provider.
* `Stop is invalid` - A selected provider in LTN in invalid (e.g., it has been deconstructed or destroyed).
* `Other force` - A provider is owned by a different force than the requester.
* `Different surface` - The provider and requester are on different surfaces that require surface connections, but LTN has none registered. This can happen if LTN runs trains on different planets but the networks have the same Id. For some mods (e.g., Space Exploration), it is possible to "connect" surfaces.
* `Minimum train length too long` - The minimum train length accepted by the provider is longer than the maximum train length accepted by the requester.
* `Maximum train length too short` - The maximum train length accepted by the provider is shorter than the minimum train length accepted by the requester.
* `Train is invalid` - A selected train in LTN is invalid (e.g., it has been deconstructed or destroyed).
* `Train is too short` - A selected train is too short to match the provider and/or requester minimum train length.
* `Train is too long` - A selected train is too long to match the provider and/or requester maximum train length.
* `No wagons` - A selected train has no wagons.

## Signals

The LTN train stop sends out signals when a train arrives:

The bit encoded (0 = front of train, 31 = back of train) composition of the train. It will report at most 31 locomotives and wagons, any locomotive and wagon after this will be ignored.

* `ltn-position-any-locomotive` for locomotives
* `ltn-position-any-cargo-wagon` for cargo wagons
* `ltn-position-any-fluid-wagon` for fluid wagons
* `ltn-position-any-artillery-wagon` for artillery wagons

e.g., a train composed of `locomotive - cargo - cargo - fluid - artillery` would send

|            | Binary | Decimal |
|------------|--------|---------|
| locomotive |  00001 |    1    |
| cargo      |  00110 |    6    |
| fluid      |  01000 |    8    |
| artillery  |  10000 |   16    |

Those signals are the same for any type of locomotives and wagons. In addition, there are specific signals for all locomotives and wagons that are defined in the game. E.g., for the standard locomotives, there is `ltn-position-locomotive`.

For provider and requester stations, the cargo and fluid in the current delivery are sent out as signals.

For any station, it will only add the amount of cargo and fluid on the current train if the `ltn-provider-show-existing-cargo` setting is true (default).

## Refueling Operations

LTN contains a limited refueling function. It is intended for simple refueling scenarios where all trains take a single type of fuel and all fuel stations for a network provide the same fuel with the same thresholds.

Starting with 2.3.0, LTN supports a new station type: 'Fuel Station'. Fuel station support must be explicitly enabled by setting the `ltn-schedule-fuel-station` setting.

Similar to a depot, there is a virtual signal that declares a stop to be a fuel station. This stop needs to receive additional signals:

- A network id signal that describes for which networks this fuel station is valid. Use `-1` for all networks.
- Fuel signals ('coal', 'wood', 'solid fuel', 'rocket fuel', 'nuclear fuel' in the base game) with a value that is used as the threshold for refueling. A fuel station does not need to send only the signals for fuels that it provides; the signals are used to create the condition for the fuel interrupt.

E.g. a station that receives 'wood' = 250 and 'rocket-fuel' = 200 for network id 1 will create a refuel interrupt for all locomotives in network 1 that will send any locomotive to this refuel stop if they use either wood or rocket fuel and the count drops under 250 for wood or 200 for rocket fuel.

If you set up refueling with LTN, consider the following things:

- __choose one type of fuel and run all trains in a network on it__. If you cannot do that, make the fuel stations "clean up" the locomotive fuel inventory. This can be done by adding an inserter to the fuel station which takes all fuel *out* of the locomotive that is not explicitly loaded at the fuel station. If a fuel station refuels using "solid-fuel", use an inserter that blacklists "solid-fuel" and takes everything else out of the locomotive.
- fuel stations may receive signals for fuel that they don't serve. E.g., receive 'wood' == 250 and 'rocket-fuel' == 200, but load only 'rocket-fuel'. When a train gets sent there, it may be because 'wood' in its fuel inventory has dropped under 250. But if the stop does not refill 'wood' into the locomotive, then it will be sent back to a refuel stop at the next opportunity until 'wood' drops to 0 (then it no longer matches the interrupt). Cleaning up the fuel inventory (see above) solves that problem.
- make sure that all fuel stations receive the same signals. Do not have one station advertising 'wood' and another that announces 'coal'. This would lead to situations where a train that needs to be refueled will be skipped because the locomotive fuel inventory does not match the fuel of the fuel station.
- Refueling works on "count of items in the inventory" as long as the count is > 0. If a fuel type disappears from the inventory because the last item was put into the burner, that fuel no longer matches (this is how the train interrupts work), and an interrupt does not trigger.

If a station receives both the depot and the fuel station signal, it is considered a depot and will not be used as a fuel station.

A fuel station has a cyan-colored station lamp to signify that it is a fuel station. Starting with 2.5.0, if a fuel station has no actual fuel signal, it will turn its lamp gray.

Trains arriving at a fuel station will leave if either all locomotives are fully fueled or there are 120 ticks (two seconds) of inactivity. When a train leaves a fuel station, the refuel interrupt is temporarily removed (it gets re-added when the train arrives at a depot that is part of a network that supports refueling).

LTN refueling is very limited and only looks at the fuel count across all locomotives. By disabling the resetting of Train Schedule interrupts and the builtin refueling support, other mods can be used to control refueling without LTN interfering.


