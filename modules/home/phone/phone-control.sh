notify() {
  notify-send --app-name="Phone control" "Phone control" "$1" 9>&- || true
}

# Keep the lock until scrcpy exits, including during discovery/connection.
# Only this launcher owns it; close FD 9 in commands that may spawn daemons.
exec 9>"$XDG_RUNTIME_DIR/phone-control.lock"
log="$XDG_RUNTIME_DIR/phone-control.log"
launch=false
if flock -n 9; then
  launch=true
  exec 2>"$log"
else
  exec 2>>"$log"
fi

# Inspect even when another launcher holds the lock: it may be waiting for
# scrcpy. Use the reserved title and a snapshot container ID, never a process name.
if ! tree="$(swaymsg -r -t get_tree 9>&-)" ||
   ! window="$(jq -r 'first(.. | objects | select(.type == "con" and .name == "phone-control") | .id) // empty' <<< "$tree" 9>&-)"; then
  notify "Cannot inspect phone window in Sway. See $log."
  exit 1
fi
if [[ "$window" =~ ^[0-9]+$ ]]; then
  if ! swaymsg -q "[con_id=$window] kill" 9>&-; then
    notify "Cannot close phone window in Sway. See $log."
    exit 1
  fi
  exit 0
fi
# During discovery/startup (or shutdown), ignore repeat presses until ready.
"$launch" || exit 0

if ! device="$(phone-adb-connect 9>&-)"; then
  notify "Cannot connect to a wireless phone. Check Wireless debugging and Wi-Fi, or disconnect extra ADB devices. See $log."
  exit 1
fi
if ! SDL_VIDEODRIVER=wayland scrcpy --serial="$device" --window-title=phone-control 9>&- >>"$log" 2>&1; then
  notify "scrcpy failed. Check Wireless debugging and try again. See $log."
  exit 1
fi
