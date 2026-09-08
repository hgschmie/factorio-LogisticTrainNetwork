# Additional documentation and manual

## Station colors

* Green - Normal Operation
* Yellow - Pending delivery operation. Station is either requester or provider.
* Blue - Train is parked at the stop.
* White - Station is not initialized.
* Red - Station is in error state.
* Cyan - Station is a refuel station.

All station colors can be read on the circuit network by connecting a green wire to the station lamp:

* Virtual Signal "green" - 1 - Normal Operation
* Virtual Signal "yellow" - n - Pending delivery operation. n is the number of trains using this stop.
* Virtual Signal "blue" - n - Train parked at the stop. n is the number of trains
* Virtual Signal "white" - Train stop is not initialized (error)
* Virtual Signal "red" - 1 - "short circuit", input (lamp), output (combinator) or the train stop connector are connected to each other
* Virtual Signal "red" - 2 - "disabled". The train stop has been disabled (e.g. through a circuit condition).
* Virtual Signal "cyan" - Train stop is a refuel station.

When using a single combinator for multiple stations (e.g. for a depot), the combinator should connect to the train stop inputs (lamps) using the *red* wire connection. This ensures that the different station lamps function correctly. When using a green wire, the virtual signals will be sent from one stop to the other and the lamps will not show the correct state. The stations will continue to function correctly, only the lamp color will be incorrect.

## Metrics

When creating a delivery, it is possible that LTN could not select a provider, even though some providers exist that should have been able to provide items or fluids. LTN prints a summary on why it could not select existing providers:

* `Network mismatch` - There is no shared LTN network between the provider and the requester.
* `No train available` - There is no train available to fulfil the delivery between a selected provider and the requester.
* `Only fluid wagons` - A delivery has items and a selected train has only fluid wagons.
* `Only cargo wagons` - A delivery has fluids and a selected train has only cargo wagons.
* `Stop is full` - The maximum number of trains defined by the provider train limit has been reached.
* `Stop is unreachable` - The game could not find any path from a depot to the provider.
* `Stop is invalid` - A selected provider in LTN in invalid (e.g. it has been deconstructed or destroyed).
* `Other force` - A provider is owned by a different force than the requester.
* `Different surface` - The provider and requester are on different surfaces and LTN has no surface connection registered. This can happen if LTN runs trains on different planets but the networks have the same Id. For some mods (e.g. Space Exploration), it is possible to "connect" surfaces.
* `Minimum train length too long` - The minimum train length accepted by the provider is longer than the maximum train length accepted by the requester.
* `Maximum train length too short` - The maximum train length accepted by the provider is shorter than the minimum train length accepted by the requester.
* `Train is invalid` - A selected train in LTN is invalid (e.g. it has been deconstructed or destroyed).
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

e.g. a train composed of `locomotive - cargo - cargo - fluid - artillery` would send

|            | Binary | Decimal |
|------------|--------|---------|
| locomotive |  00001 |    1    |
| cargo      |  00110 |    6    |
| fluid      |  01000 |    8    |
| artillery  |  10000 |   16    |

Those signals are the same for any type of locomotives and wagons. In addition, there are specific signals for all locomotives and wagons that are defined in the game. E.g. for the standard locomotives, there is `ltn-position-locomotive`.

For provider and requester stations, the cargo and fluid in the current delivery are sent out as signals.

For any station, it will also add the amount of cargo and fluid on the current train unless the `ltn-provider-ignore-stopped-train` setting is true.
