{pkgs, ...}:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  
  environment.systemPackages = with pkgs; [
   sddm-astronaut
  ];

  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm;   
    wayland.enable = true;
    theme = "sddm-astronaut-theme";


    extraPackages = with pkgs; [
      sddm-astronaut
      kdePackages.qtmultimedia
      kdePackages.qtsvg
      kdePackages.qtvirtualkeyboard
    ];
  };
  
  xdg.portal = {
    enable = true;
 
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk

   
    ];

    config.hyprland = {
      default = [ "hyprland" "gtk" ];
    };
  };
}
