{ pkgs, ... }:

let
  clipboardPicker = pkgs.writeShellApplication {
    name = "clipboard-picker";

    runtimeInputs = with pkgs; [
      cliphist
      fuzzel
      wl-clipboard
    ];

    text = ''
      selection="$(
        cliphist list |
          fuzzel \
            --dmenu \
            --prompt="Clipboard > " \
            --width=70 \
            --lines=15
      )"

      if [ -z "$selection" ]; then
        exit 0
      fi

      printf '%s\n' "$selection" |
        cliphist decode |
        wl-copy
    '';
  };
in
{
  services.cliphist = {
    enable = true;

    # Keep copied images as well as text.
    allowImages = true;

    # Start/stop with the actual Sway session.
    systemdTargets = [
      "sway-session.target"
    ];
  };

  home.packages = [
    clipboardPicker
  ];
}

