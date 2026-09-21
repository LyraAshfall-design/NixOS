-- Physical desktop workspace layout
-- 3 persistent workspaces per monitor.

for i = 1, NUM_WPM do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = MONITOR1,
        persistent = true
    })

    hl.workspace_rule({
        workspace = tostring(i + NUM_WPM),
        monitor = MONITOR2,
        persistent = true
    })
end
