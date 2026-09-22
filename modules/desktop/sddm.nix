{ config, lib, pkgs, ... }:

let
  colors = config.home-manager.users.corey.catCafe.colors;
  desktop = config.networking.hostName == "nixos-desktop";
  # Isolated greeter compositor: no user config, bindings or session startup.
  # Layer-shell lets SDDM place one complete theme view on each named output.
  greeterConfig = pkgs.writeText "sddm-sway.conf" ''
    output DP-3 mode 1920x1080 position 0 0 scale 1
    output DP-2 mode 1920x1080 position 1920 0 scale 1
    input * {
      xkb_model ${config.services.xserver.xkb.model}
      xkb_layout ${config.services.xserver.xkb.layout}
    }
    xwayland disable
  '';
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
      wayland.compositorCommand = lib.mkIf desktop
        "${pkgs.sway-unwrapped}/bin/sway --unsupported-gpu --config ${greeterConfig}";
      extraPackages = lib.optionals desktop [ pkgs.kdePackages.layer-shell-qt ];
      # Preserve SilentSDDM's QML imports and keyboard integration while adding
      # per-output layer surfaces. This environment belongs only to the greeter.
      settings.General.GreeterEnvironment = lib.mkIf desktop (lib.mkForce
        "QML2_IMPORT_PATH=${config.programs.silentSDDM.package'}/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard,QT_WAYLAND_SHELL_INTEGRATION=layer-shell");
    };
  };

  # Official module supplies the theme, fonts and matching Qt6/QML dependencies.
  # The static bundled coffee image is store-readable by the greeter; it does
  # not depend on access to Corey's home or a running wallpaper service.
  programs.silentSDDM = {
    enable = true;
    theme = "default";
    backgrounds.coffee = ../../assets/sddm/coffee.jpg;
    backgrounds."cat-mark" = ../../assets/theme/cat-mark.svg;
    settings = {
      General.enable-animations = false;
      LockScreen = {
        background = "coffee.jpg";
        background-color = colors.mantle;
        blur = 0;
        brightness = -0.3;
        saturation = -0.1;
      };
      "LockScreen.Clock" = { color = colors.text; font-size = 54; font-weight = 500; };
      "LockScreen.Date".color = colors.muted;
      "LockScreen.Message" = {
        color = colors.muted;
        icon = "../backgrounds/cat-mark.svg";
        icon-size = 42;
      };
      LoginScreen = {
        background = "coffee.jpg";
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
        icon = "../backgrounds/cat-mark.svg";
        icon-size = 22;
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
