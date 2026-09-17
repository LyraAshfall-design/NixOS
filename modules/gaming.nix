{ pkgs, ... }:

{
  # Hardware-accelerated graphics.
  # 32-bit graphics libraries are required by Steam/Proton.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Native Steam installation.
  programs.steam = {
    enable = true;

    # Community Proton build with newer compatibility fixes.
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # Allows games to temporarily request performance-oriented scheduling.
  programs.gamemode.enable = true;

  # Optional nested gaming compositor useful for some games/setups.
  programs.gamescope = {
    enable = true;

    # Allows Gamescope to adjust process scheduling priority.
    capSysNice = true;
  };
}
