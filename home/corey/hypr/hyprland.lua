-- CachyOS Hyprland Configuration

require("config.animations")
require("config.colors")
require("config.decorations")
require("config.variables")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.monitors")

if hl.get_monitor(MONITOR1) ~= nil and hl.get_monitor(MONITOR2) ~= nil then
    require("config.monitor-recovery")
end

require("config.windowrules")
require("config.workspaces")
