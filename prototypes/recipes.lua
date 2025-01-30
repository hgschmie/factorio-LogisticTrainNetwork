--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

local ltn_stop = flib.copy_prototype(data.raw['recipe']['train-stop'], 'logistic-train-stop')
ltn_stop.ingredients = {
    { type = 'item', name = 'train-stop',          amount = 1 },
    { type = 'item', name = 'constant-combinator', amount = 1 },
    { type = 'item', name = 'small-lamp',          amount = 1 },
}
ltn_stop.enabled = false

data:extend {
    ltn_stop
}

-- support for cargo ship ports
if mods['cargo-ships'] then
    ltn_port = flib.copy_prototype(data.raw['recipe']['port'], 'ltn-port')
    ltn_port.ingredients = {
        { type = 'item', name = 'port',                amount = 1 },
        { type = 'item', name = 'constant-combinator', amount = 1 },
        { type = 'item', name = 'small-lamp',          amount = 1 },
    }
    ltn_port.enabled = false

    data:extend {
        ltn_port
    }
end
