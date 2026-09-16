-- Physical left monitor
hl.monitor({
    output = MONITOR2,
    mode = "1920x1080@180",
    position = "0x0",
    scale = 1,
})

-- Physical right monitor
hl.monitor({
    output = MONITOR1,
    mode = "1920x1080@180",
    position = "1920x0",
    scale = 1,
})

-- Fallback for any other display, including VMs
hl.monitor({
    output = "",
    mode = "1920x1080@60",
    position = "auto",
    scale = 1,
})
