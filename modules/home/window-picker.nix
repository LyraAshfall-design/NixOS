{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "sway-window-picker";
      runtimeInputs = with pkgs; [ sway jq fuzzel ];
      text = ''
        # Include native Wayland and XWayland windows, including scratchpad.
        entries="$(swaymsg -t get_tree | jq -r '
          recurse(.nodes[]?, .floating_nodes[]?) |
          select(.type == "con" and (.app_id != null or .window != null)) |
          "\(.id)\t\(.app_id // .window_properties.class // "Window") — \(.name // "Untitled" | gsub("[\\r\\n\\t]"; " "))"
        ')"
        [ -n "$entries" ] || exit 0
        choice="$(printf '%s\n' "$entries" | fuzzel --dmenu --prompt="Window > " --width=80)" || exit 0
        id="''${choice%%$'\t'*}"
        # Never interpolate a title or arbitrary Fuzzel input into Sway IPC.
        [[ "$id" =~ ^[0-9]+$ ]] || exit 0
        swaymsg "[con_id=$id] focus"
      '';
    })
  ];
}
