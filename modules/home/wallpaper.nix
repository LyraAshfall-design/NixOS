{ pkgs, ... }:

{
  home.packages = with pkgs; [
    curl
    jq
    imagemagick
    coreutils
    gnugrep
    gawk
  ];

  home.file.".local/bin/wallpaper-next" = {
    source = ../../home/corey/scripts/wallpaper-next.sh;
    executable = true;
  };

  systemd.user.services.sway-wallpaper = {
    Unit = {
      Description = "Restore Sway wallpaper";
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "oneshot";

      ExecStart = pkgs.writeShellScript "restore-sway-wallpaper" ''
        current="$HOME/Pictures/wallpapers/current"

        if [ -e "$current" ]; then
          ${pkgs.sway}/bin/swaymsg output "*" bg "$current" fill
        fi
      '';
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}
