{ pkgs, ... }:

let
  adbConnect = pkgs.writeShellApplication {
    name = "phone-adb-connect";
    runtimeInputs = with pkgs; [ android-tools avahi coreutils gawk ];
    text = builtins.readFile ./phone/phone-adb-connect.sh;
  };
  phoneControl = pkgs.writeShellApplication {
    name = "phone-control";
    runtimeInputs = with pkgs; [ adbConnect scrcpy libnotify util-linux ];
    text = builtins.readFile ./phone/phone-control.sh;
  };
  photoImport = pkgs.writeShellApplication {
    name = "phone-photo-import";
    runtimeInputs = with pkgs; [ adbConnect android-tools python3 ];
    text = ''
      exec python3 ${./phone/phone-photo-import.py} "$@"
    '';
  };
in
{
  home.packages = [ phoneControl photoImport ];

  systemd.user.services.phone-photo-import = {
    Unit.Description = "Archive phone camera files over wireless ADB (one way)";
    Service = {
      Type = "oneshot";
      ExecStart = "${photoImport}/bin/phone-photo-import";
      # A first import can take a long time; individual ADB operations are bounded.
      TimeoutStartSec = "infinity";
      UMask = "0077";
    };
  };
  systemd.user.timers.phone-photo-import = {
    Unit.Description = "Import new phone camera files every 30 minutes";
    Timer = {
      OnCalendar = "*-*-* *:00,30:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
