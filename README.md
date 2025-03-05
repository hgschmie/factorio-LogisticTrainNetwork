# Factorio - Logistic Train Network

Factorio mod  adding "logistic-train-stops" acting as anchor points for building a train powered logistic network.

It can handle multiple train configurations and will pick the best available train for a delivery.

## Factorio 2.0 Updates

LTN has been ported to Factorio 2.0. It will get minimal updates (only really glaring bugs). The current plan is to provide a successor that takes advantage of the improved 2.0 trains while maintaining the ease of scheduling and dispatching with LTN.

The most common request for LTN is "please support Factorio 2.0 train interrupts". As much as this is desirable, currently, _there is no Factorio mod API_ to manage interrupts and changing the schedule of a train resets all interrupts. As soon as the Factorio developers add the necessary APIs, LTN will be updated accordingly.

### Train Schedule Interrupts (since 2.3.0)

Factorio 2.0 trains support "Train Schedule Interrupts" which trigger under certain conditions. Starting with 2.3.0, LTN will not change any interrupts in the train schedule unless explicitly configured with the `ltn-schedule-reset-interrupts` setting.

### Refueling support (since 2.3.0)

Starting with 2.3.0, LTN supports a new station type: 'Fuel Station'. Fuel station support must be explicitly enabled by setting the `ltn-schedule-fuel-station` setting.

Similar to a depot, there is a virtual signal that declares a stop to be a fuel station. This stop needs to receive additional signals:

- A network id signal that describes for which networks this fuel station is valid. Use `-1` for all networks.
- Fuel signals ('coal', 'wood', 'solid fuel', 'rocket fuel', 'nuclear fuel' in the base game) with a value that is used as the threshold for refueling. A fuel station does not need to send only the signals for fuels that it provides; the signals are used to create the condition for the fuel interrupt.

E.g. a station that receives 'wood' = 250 and 'rocket-fuel' = 200 for network id 1 will create a refuel interrupt for all locomotives in the network 1 that will send any locomotive to this refuel stop if they use either wood or rocket fuel and the count drops under 250 for wood or 200 for rocket fuel.

If a station receives both the depot and the fuel station signal, it is considered a depot and will not be used as a fuel station.

A fuel station has a cyan-colored station lamp to signify that it is a fuel station.

Trains arriving at a fuel station will leave if either all locomotives are fully fueled or there are 120 ticks (two seconds) of inactivity. When a train leaves a fuel station, the refuel interrupt is temporarily removed (it gets re-added when the train arrives at a depot that is part of a network that supports refueling).

LTN refueling is very limited and only looks at the fuel count across all locomotives. By disabling the resetting of Train Schedule interrupts and the builtin refueling support, other mods can be used to control refueling without LTN interfering.

### Depot changing (since 2.3.0)

A train that is added to the LTN network will return to a depot when it finishes a delivery. If the 'ltn-dispatcher-requester-delivery-reset` setting is unset, a train will always return to the depot it was assigned to (the depot that it was sent to when it registered with the LTN network).

If this setting turned on, then LTN will as soon as the train leaves the requester, select one of the depots that accepts trains in the current network at random. Trains may go to a different depot in that case. This is especially important if a depot serves multiple networks. A train that gets sent to a depot that serves multiple networks becomes eligible to requests in those networks (assuming that capacity, length etc. also match).

### API

[LTN Settings Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/SETTINGS.md)
[LTN API Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/API.md)

Starting with version 2.1.0, LTN supports quality for requester and provider signals. To support this, there are a few _minimal_, _backwards compatible_ API changes. If you maintain a mod that uses the LTN remote API, the changes are documented [LTN API Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/API.md#changelog)

### Contact

- [Forum](https://mods.factorio.com/mod/LogisticTrainNetwork/discussion) (changed from pre-2.0!)
- [Bug Reports](https://github.com/hgschmie/factorio-LogisticTrainNetwork/issues)
- [Source Code](https://github.com/hgschmie/factorio-LogisticTrainNetwork)
- [Download](https://mods.factorio.com/mod/LogisticTrainNetwork/downloads)
- [Manual (on the LTN subforum)](https://forums.factorio.com/viewtopic.php?f=214&t=51072)

### How you can help

If you maintain an LTN mod and stopped working on it, consider porting it to 2.0!

----

## Legal

LTN is (C) 2017-2018 by Optera [under a restrictive license](LICENSE.md).

The 2.0 port is maintained with permission by @hgschmie
