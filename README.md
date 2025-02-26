# Factorio - Logistic Train Network

Factorio mod  adding "logistic-train-stops" acting as anchor points for building a train powered logistic network.

It can handle multiple train configurations and will pick the best available train for a delivery.

## Factorio 2.0 Updates

LTN has been ported to Factorio 2.0. It will get minimal updates (only really glaring bugs). The current plan is to provide a successor that takes advantage of the improved 2.0 trains while maintaining the ease of scheduling and dispatching with LTN.

The most common request for LTN is "please support Factorio 2.0 train interrupts". As much as this is desirable, currently, _there is no Factorio mod API_ to manage interrupts and changing the schedule of a train resets all interrupts. As soon as the Factorio developers add the necessary APIs, LTN will be updated accordingly.

### API

[LTN Settings Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/SETTINGS.md)
[LTN API Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/API.md)

Starting with version 2.1.0, LTN supports quality for requester and provider signals. To support this, there are a few _minimal_, _backwards compatible_ API changes. If you maintain a mod that uses the LTN remote API, the changes are documented [LTN API Documentation](https://github.com/hgschmie/factorio-LogisticTrainNetwork/blob/master/API.md#changelog)

### Contact

* [Forum](https://mods.factorio.com/mod/LogisticTrainNetwork/discussion) (changed from pre-2.0!)
* [Bug Reports](https://github.com/hgschmie/factorio-LogisticTrainNetwork/issues)
* [Source Code](https://github.com/hgschmie/factorio-LogisticTrainNetwork)
* [Download](https://mods.factorio.com/mod/LogisticTrainNetwork/downloads)

* [Manual (on the LTN subforum)](https://forums.factorio.com/viewtopic.php?f=214&t=51072)

### How you can help

If you maintain an LTN mod and stopped working on it, consider porting it to 2.0!

----

## Legal

LTN is (C) 2017-2018 by Optera [under a restrictive license](LICENSE.md).

The 2.0 port is maintained with permission by @hgschmie
