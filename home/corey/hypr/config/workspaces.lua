-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your workspace rules here. Increment the workspace number as you go. Do not have duplicate workspaces.
-- Workspace configuration

local hasMonitor1 = hl.get_monitor(MONITOR1) ~= nil
local hasMonitor2 = hl.get_monitor(MONITOR2) ~= nil

if hasMonitor1 and hasMonitor2 then
    -- Physical desktop: 3 workspaces per monitor
    hl.workspace_rule({
        workspace = "name:gaming",
        monitor = PRIMARY_MONITOR
    })

    for i = 1, NUM_WPM do
        hl.workspace_rule({
            workspace = tostring(i),
            monitor = MONITOR1,
            default = true,
            persistent = true
        })

        hl.workspace_rule({
            workspace = tostring(i + NUM_WPM),
            monitor = MONITOR2,
            default = true,
            persistent = true
        })
    end
else
    -- Single-monitor fallback: VM, laptop, etc.
    hl.workspace_rule({
        workspace = "name:gaming"
    })

    for i = 1, NUM_WPM * 2 do
        hl.workspace_rule({
            workspace = tostring(i),
            persistent = true
        })
    end
end
