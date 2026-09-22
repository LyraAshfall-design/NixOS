{ pkgs, ... }:

{
  services.swayidle = {
    enable = true;

    systemdTargets = [
      "sway-session.target"
    ];

    events = {
      # Lock immediately before suspend.
      before-sleep =
        "${pkgs.swaylock}/bin/swaylock -f";

      # Also respond correctly if logind asks the session to lock.
      lock =
        "${pkgs.swaylock}/bin/swaylock -f";
    };

    timeouts = [
      {
        # Lock after 10 minutes idle.
        timeout = 600;
        command =
          "${pkgs.swaylock}/bin/swaylock -f";
      }

      {
        # Power displays off after 15 minutes idle.
        timeout = 900;
        command =
          "${pkgs.sway}/bin/swaymsg 'output * power off'";

        # Wake displays again on input.
        resumeCommand =
          "${pkgs.sway}/bin/swaymsg 'output * power on'";
      }
    ];
  };
}
