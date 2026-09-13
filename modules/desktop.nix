{pkgs, ...}:

{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
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
