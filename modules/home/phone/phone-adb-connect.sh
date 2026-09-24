connected_devices() {
  local devices
  devices="$(timeout 5 adb devices)" || return 1
  # ADB uses either host:port or an mDNS service name for Wi-Fi serials.
  # Exclude offline/unauthorized devices, USB serials, and emulators.
  awk '$2 == "device" && ($1 ~ /:[0-9]+$/ || $1 ~ /\._adb-tls-connect\._tcp\.?$/) {print $1}' <<< "$devices"
}

if ! devices="$(connected_devices)"; then
  echo "ADB is unavailable." >&2
  exit 1
fi

if [[ -z "$devices" ]]; then
  # Browse for five seconds to allow fresh announcements and resolution.
  # Only the connection service is useful here, never the pairing port.
  services="$(timeout 5 avahi-browse --resolve --parsable _adb-tls-connect._tcp)" || true
  endpoints="$(awk -F ';' '
    $1 == "=" && $5 == "_adb-tls-connect._tcp" && $9 ~ /^[0-9]+$/ {
      if ($8 ~ /^fe80:/) $8 = $8 "%" $2;
      if (index($8, ":")) print "[" $8 "]:" $9;
      else print $8 ":" $9;
    }
  ' <<< "$services" | sort -u)"

  while IFS= read -r endpoint; do
    [[ -n "$endpoint" ]] || continue
    # adb connect can report failure with exit status zero; inspect the
    # actual device state below instead of trusting its exit status.
    timeout 5 adb connect "$endpoint" >&2 || true
    devices="$(connected_devices)" || devices=""
    [[ -z "$devices" ]] || break
  done <<< "$endpoints"
  devices="$(connected_devices)" || devices=""
fi

if [[ -z "$devices" ]]; then
  echo "No wireless phone connected; check Wireless debugging and Wi-Fi." >&2
  exit 1
fi

if [[ "$devices" == *$'\n'* ]]; then
  echo "Multiple wireless ADB connections found; disconnect extras first." >&2
  exit 1
fi

printf '%s\n' "$devices"
