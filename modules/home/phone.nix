{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "phone-control";
      runtimeInputs = with pkgs; [ android-tools scrcpy avahi libnotify util-linux coreutils gawk ];
      text = ''
        notify() {
          notify-send --app-name="Phone control" "Phone control" "$1" || true
        }

        # Keep the lock until scrcpy exits, including during discovery/connection.
        exec 9>"$XDG_RUNTIME_DIR/phone-control.lock"
        flock -n 9 || exit 0
        log="$XDG_RUNTIME_DIR/phone-control.log"
        exec 2>"$log"

        connected_devices() {
          local devices
          devices="$(timeout 5 adb devices)" || return 1
          # ADB uses either host:port or an mDNS service name for Wi-Fi serials.
          # Exclude offline/unauthorized devices, USB serials, and emulators.
          awk '$2 == "device" && ($1 ~ /:[0-9]+$/ || $1 ~ /\._adb-tls-connect\._tcp\.?$/) {print $1}' <<< "$devices"
        }

        if ! devices="$(connected_devices)"; then
          notify "ADB is unavailable. See $log."
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
            timeout 5 adb connect "$endpoint" >>"$log" 2>&1 || true
            devices="$(connected_devices)" || devices=""
            [[ -z "$devices" ]] || break
          done <<< "$endpoints"
          devices="$(connected_devices)" || devices=""
        fi

        if [[ -z "$devices" ]]; then
          notify "No wireless phone connected. Unlock the phone, enable Wireless debugging, and check that both devices are on the same Wi-Fi. See $log."
          exit 1
        fi

        if [[ "$devices" == *$'\n'* ]]; then
          notify "Multiple wireless ADB connections found. Disconnect the extra connections with adb disconnect, then try again."
          exit 1
        fi

        if ! scrcpy --serial="$devices" >>"$log" 2>&1; then
          notify "scrcpy failed. Check Wireless debugging and try again. See $log."
          exit 1
        fi
      '';
    })
  ];
}
