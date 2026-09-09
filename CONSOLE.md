# LTN Console

## List locomotives excluded from refueling - `/ltn-list-refuel-excluded`

Lists all locomotives that are not refueled by the internal refuel stations. These locomotives have been registered through the `exclude_from_fuel_schedule` API.

## List all stops that do not have a network id - `/ltn-list-no-network-id`

Lists all LTN stops that do not have a network id supplied. This is relevant if the default network id is 0 (recommended setting) and no network id signal is supplied (either missing from the circuit network or a connected combinator has been turned off).

## List all stops that use the default network id - `/ltn-list-default-network-id`

Lists all LTN stops that use the default network id. This is only relevant if the default network id is not 0. All stops that either have a circuit signal supplying the default network id or no circuit signal supplying a network id are listed (if no network id signal is present, the default network id is used).
