{ pkgs, ... }:

let
  screenshotRegion = pkgs.writeShellApplication {
    name = "screenshot-region";

    runtimeInputs = with pkgs; [
      grim
      slurp
      satty
    ];

    text = ''
      geometry="$(slurp)" || exit 0
      grim -g "$geometry" - | satty -f -
    '';
  };

  screenshotFullscreen = pkgs.writeShellApplication {
    name = "screenshot-fullscreen";

    runtimeInputs = with pkgs; [
      grim
      satty
    ];

    text = ''
      grim - | satty -f -
    '';
  };
in
{
  home.packages = [
    screenshotRegion
    screenshotFullscreen
  ];
}
