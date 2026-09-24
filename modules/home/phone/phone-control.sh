notify() {
  notify-send --app-name="Phone control" "Phone control" "$1" || true
}

# Keep the lock until scrcpy exits, including during discovery/connection.
exec 9>"$XDG_RUNTIME_DIR/phone-control.lock"
flock -n 9 || exit 0
log="$XDG_RUNTIME_DIR/phone-control.log"
exec 2>"$log"

if ! device="$(phone-adb-connect)"; then
  notify "Cannot connect to a wireless phone. Check Wireless debugging and Wi-Fi, or disconnect extra ADB devices. See $log."
  exit 1
fi
if ! scrcpy --serial="$device" >>"$log" 2>&1; then
  notify "scrcpy failed. Check Wireless debugging and try again. See $log."
  exit 1
fi
