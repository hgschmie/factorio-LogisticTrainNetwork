--[[ Copyright (c) 2017 Optera
 * Part of Logistics Train Network
 *
 * See LICENSE.md in the project directory for license information.
--]]

require('script.constants')
require('script.settings')
require('script.alert')
require('script.hotkey-events') -- requires print

require('script.stop-update')
require('script.dispatcher')
require('script.stop-events')
require('script.train-events')
require('script.train-interface')   -- requires train-events
require('script.surface-interface') -- requires stop-events
require('script.interface')         -- ties into other modules
require('script.init')              -- requires other modules loaded first
