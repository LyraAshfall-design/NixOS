{ config, pkgs, ... }:

let
  colors = config.home-manager.users.corey.catCafe.colors;
  menu = {
    background-color = colors.surface;
    background-opacity = 0.8;
    active-background-opacity = 1.0;
    content-color = colors.muted;
    active-content-color = colors.accent;
  };
in
{
  services.displayManager = {
    defaultSession = "sway";
    sddm = {
      enable = true;
      package = pkgs.kdePackages.sddm;
      wayland.enable = true;
    };
  };

  # Official module supplies the theme, fonts and matching Qt6/QML dependencies.
  # The static bundled woodland photo is store-readable by the greeter; it does
  # not depend on access to Corey's home or a running wallpaper service.
  programs.silentSDDM = {
    enable = true;
    theme = "default";
    settings = {
      General.enable-animations = false;
      LockScreen = {
        background = "default.jpg";
        background-color = colors.mantle;
        blur = 0;
        brightness = -0.3;
        saturation = -0.1;
      };
      "LockScreen.Clock" = { color = colors.text; font-size = 54; font-weight = 500; };
      "LockScreen.Date".color = colors.muted;
      "LockScreen.Message".color = colors.muted;
      LoginScreen = {
        background = "default.jpg";
        background-color = colors.mantle;
        blur = 0;
        brightness = -0.3;
        saturation = -0.1;
      };
      "LoginScreen.LoginArea.Avatar" = {
        active-size = 80;
        inactive-size = 56;
        active-border-size = 1;
        active-border-color = colors.accent;
        inactive-border-color = colors.overlay;
      };
      "LoginScreen.LoginArea.Username".color = colors.text;
      "LoginScreen.LoginArea.PasswordInput" = {
        content-color = colors.text;
        background-color = colors.base;
        background-opacity = 0.95;
        border-size = 1;
        border-color = colors.accent;
      };
      "LoginScreen.LoginArea.LoginButton" = {
        background-color = colors.surface;
        background-opacity = 0.95;
        active-background-color = colors.accent;
        active-background-opacity = 1.0;
        content-color = colors.text;
        active-content-color = colors.base;
        border-size = 1;
        border-color = colors.overlay;
      };
      "LoginScreen.LoginArea.Spinner".color = colors.accent;
      "LoginScreen.LoginArea.WarningMessage" = {
        normal-color = colors.text;
        warning-color = colors.warning;
        error-color = colors.urgent;
      };
      "LoginScreen.MenuArea.Session" = menu // { display = true; display-session-name = true; };
      "LoginScreen.MenuArea.Power" = menu // { display = true; };
      "LoginScreen.MenuArea.Layout" = menu;
      "LoginScreen.MenuArea.Keyboard" = menu;
      "LoginScreen.MenuArea.Popups" = {
        background-color = colors.base;
        background-opacity = 0.95;
        active-option-background-color = colors.accent;
        active-option-background-opacity = 1.0;
        content-color = colors.text;
        active-content-color = colors.base;
        border-size = 1;
        border-color = colors.overlay;
      };
      "LoginScreen.VirtualKeyboard" = {
        background-color = colors.base;
        key-content-color = colors.text;
        key-color = colors.surface;
        key-active-background-color = colors.accent;
        selection-background-color = colors.accent;
        selection-content-color = colors.base;
        primary-color = colors.accent;
        border-color = colors.overlay;
      };
      Tooltips = {
        content-color = colors.text;
        background-color = colors.surface;
        background-opacity = 0.95;
      };
    };
  };
}
