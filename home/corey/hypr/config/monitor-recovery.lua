-- Automatic recovery for Corey's two 1080p / 180 Hz monitors.
-- Hyprland 0.56.2 (Lua config).
--
-- Save as ~/.config/hypr/config/monitor-recovery.lua.
-- Session test: hyprctl eval 'require("config.monitor-recovery")'
-- Persistent setup: require("config.monitor-recovery") in hyprland.lua,
-- after the existing monitor configuration. Keep the saved monitor rules
-- enabled at 180 Hz; a config reload cancels these timers and restores them.
--
-- This automates the tested disable / wait two seconds / re-enable recovery.
-- It is a workaround, and workspaces can migrate during the reset.
-- Startup connections do not trigger resets: a removal must be seen first.
-- Diagnostics v2: inspect with hyprctl repl 'monitor_recovery_status()'.
-- The trace is kept in memory and is reset on a Hyprland config reload.

local outputs = {
    ["DP-2"] = { position = "1920x0" }, -- Right
    ["DP-3"] = { position = "0x0" },    -- Left
}

local order = { "DP-2", "DP-3" }
local state = {}
local resetting = nil
local loaded_at = os.date("%Y-%m-%d %H:%M:%S")
local history = {}

local function trace(message)
    history[#history + 1] = os.date("%H:%M:%S") .. " " .. message
    if #history > 64 then table.remove(history, 1) end
end

local function guarded(label, callback)
    return function(...)
        local ok, message = pcall(callback, ...)
        if not ok then trace("ERROR " .. label .. ": " .. tostring(message)) end
    end
end

for name in pairs(outputs) do
    state[name] = {
        removed = false, ready = false, generation = 0,
        disable_calls = 0, enable_calls = 0,
    }
end

local function later(delay, label, callback)
    hl.timer(guarded("timer " .. label, callback), { timeout = delay, type = "oneshot" })
end

local function awake(name)
    local monitor = hl.get_monitor(name)
    return monitor and monitor.dpms_status
end

local run_next
run_next = function()
    if resetting then
        trace("Queue waiting for " .. resetting .. " reset/cooldown")
        return
    end

    -- Keep another output available, including when both are power-cycled.
    local available = 0
    local seen = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.dpms_status then available = available + 1 end
        seen[#seen + 1] = tostring(monitor.name) .. ":dpms=" .. tostring(monitor.dpms_status)
    end
    if available < 2 then
        trace("Queue paused: fewer than two awake outputs (" .. table.concat(seen, ", ") .. ")")
        return
    end

    for _, name in ipairs(order) do
        local current = state[name]
        if current.ready and not awake(name) then
            trace(name .. ": reset queued, but output is absent or DPMS is off")
        end
        if current.ready and awake(name) then
            resetting = name
            current.ready = false
            trace(name .. ": reset starting")

            -- Arrange restoration before disabling the output.
            later(2000, name .. " re-enable", function()
                -- Ignore this reset's own disconnect/reconnect events until
                -- five seconds after requesting re-enable. Serialize resets.
                later(5000, name .. " cooldown", function()
                    current.removed = false
                    current.ready = false
                    resetting = nil
                    trace(name .. ": cooldown ended")
                    run_next()
                end)

                current.enable_calls = current.enable_calls + 1
                trace(name .. ": requesting re-enable at 1920x1080@180")
                hl.monitor({
                    output   = name,
                    disabled = false,
                    mode     = "1920x1080@180",
                    position = outputs[name].position,
                    scale    = 1,
                })
                trace(name .. ": re-enable call returned")
            end)

            current.disable_calls = current.disable_calls + 1
            trace(name .. ": requesting disable")
            hl.monitor({ output = name, disabled = true })
            trace(name .. ": disable call returned")
            return
        end
    end
end

hl.on("monitor.removed", guarded("monitor.removed", function(monitor)
    local name = monitor.name
    local current = state[name]
    trace("Event monitor.removed: " .. tostring(name))
    if not current then return end
    if resetting == name then
        trace(name .. ": ignoring removal during own reset/cooldown")
        return
    end

    current.generation = current.generation + 1
    current.removed = true
    current.ready = false
end))

hl.on("monitor.added", guarded("monitor.added", function(monitor)
    local name = monitor.name
    trace("Event monitor.added: " .. tostring(name))
    if resetting == name then
        trace(name .. ": ignoring addition during own reset/cooldown")
        return
    end

    local current = state[name]
    if current and current.removed then
        current.removed = false
        local generation = current.generation
        trace(name .. ": reconnect accepted; waiting 3000 ms")

        -- Let the physical connection settle. A further removal cancels this.
        later(3000, name .. " reconnect", function()
            if current.generation ~= generation then
                trace(name .. ": cancelled stale reconnect timer")
                return
            end
            trace(name .. ": reconnect timer fired")
            current.ready = true
            run_next()
        end)
    else
        trace(tostring(name) .. ": no preceding removal recorded; no new reset queued")
        run_next()
    end
end))

-- A stable name makes the trace accessible without requiring/reloading the file.
-- Requiring a missing module here would start a fresh trace and hide a reload.
function monitor_recovery_status()
    local lines = {
        "Monitor recovery diagnostics v2; loaded " .. loaded_at,
        "Reset/cooldown in progress: " .. tostring(resetting),
    }
    for _, name in ipairs(order) do
        local current = state[name]
        lines[#lines + 1] = string.format(
            "%s: removed=%s ready=%s disable_calls=%d enable_calls=%d",
            name, tostring(current.removed), tostring(current.ready),
            current.disable_calls, current.enable_calls
        )
    end
    for _, line in ipairs(history) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

trace("Diagnostic module loaded; waiting for a physical removal and reconnect")
later(1000, "self-check", function() trace("Timer self-check fired") end)

return { version = 2, status = monitor_recovery_status }
