{ pkgs, lib, ... }:

let
  # Muted wood-brown folders complement caramel without replacing app branding.
  # Select the variant at build time; never mutate installed icons at login.
  iconTheme = {
    name = "Papirus-Dark";
    package = pkgs.papirus-icon-theme.override { color = "brown"; };
  };
  # Warm cat-cafe palette: espresso, oat cream, caramel and muted botanicals.
  # All desktop color values originate here; alpha stays with each component.
  palette = {
    mantle = [ 23 19 17 ];       # #171311
    base = [ 33 27 24 ];         # #211b18
    surface = [ 45 37 33 ];      # #2d2521
    overlay = [ 65 54 49 ];      # #413631
    text = [ 232 220 203 ];      # #e8dccb
    muted = [ 201 184 164 ];     # #c9b8a4
    accent = [ 209 154 102 ];    # #d19a66
    secondary = [ 201 123 99 ];  # #c97b63
    sage = [ 158 170 131 ];      # #9eaa83
    warning = [ 214 181 109 ];   # #d6b56d
    urgent = [ 201 130 134 ];    # #c98286
    # Distinct ANSI hues keep terminal diagnostics and syntax readable.
    ansiBlue = [ 143 167 173 ];
    ansiMagenta = [ 185 141 145 ];
    ansiCyan = [ 145 171 160 ];
    brightBlack = [ 141 123 109 ];
    brightRed = [ 222 157 159 ];
    brightGreen = [ 183 193 158 ];
    brightYellow = [ 232 202 143 ];
    brightBlue = [ 173 193 196 ];
    brightMagenta = [ 212 170 174 ];
    brightCyan = [ 175 198 184 ];
    brightWhite = [ 245 235 222 ];
  };
  hex = name: "#" + lib.concatMapStrings
    (n: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString n))) palette.${name};
  rgb = name: lib.concatMapStringsSep "," toString palette.${name};
  gtkColors = {
    accent_color = "accent";
    accent_bg_color = "accent";
    accent_fg_color = "base";
    window_bg_color = "base";
    window_fg_color = "text";
    view_bg_color = "mantle";
    view_fg_color = "text";
    headerbar_bg_color = "surface";
    headerbar_fg_color = "text";
    headerbar_backdrop_color = "base";
    popover_bg_color = "surface";
    popover_fg_color = "text";
    card_bg_color = "surface";
    card_fg_color = "text";
    dialog_bg_color = "base";
    dialog_fg_color = "text";
    sidebar_bg_color = "mantle";
    sidebar_fg_color = "text";
    destructive_color = "urgent";
    destructive_bg_color = "urgent";
    destructive_fg_color = "base";
    error_color = "urgent";
    success_color = "sage";
    warning_color = "warning";
    theme_bg_color = "base";
    theme_fg_color = "text";
    theme_base_color = "mantle";
    theme_text_color = "text";
    theme_selected_bg_color = "accent";
    theme_selected_fg_color = "base";
    insensitive_fg_color = "muted";
    borders = "overlay";
  };
  gtkCss = lib.concatStrings (lib.mapAttrsToList
    (name: color: "@define-color ${name} ${hex color};\n") gtkColors);
  # Qt QPalette roles, in qt6ct's serialization order (WindowText through PlaceholderText).
  qtColors = disabled: lib.concatMapStringsSep ", " hex [
    (if disabled then "muted" else "text") "surface" "overlay" "surface"
    "mantle" "overlay" (if disabled then "muted" else "text") "text"
    (if disabled then "muted" else "text") "mantle" "base" "mantle"
    "accent" "base" "accent" "secondary" "base" "text" "surface" "text" "muted"
  ];
  qtPalette = pkgs.writeText "sway-qt.colors" (lib.generators.toINI { } {
    ColorScheme = {
      active_colors = qtColors false;
      inactive_colors = qtColors false;
      disabled_colors = qtColors true;
    };
  });
  kdeColors = background: {
    BackgroundNormal = rgb background;
    BackgroundAlternate = rgb "surface";
    ForegroundNormal = rgb "text";
    ForegroundInactive = rgb "muted";
    ForegroundActive = rgb "accent";
    ForegroundLink = rgb "accent";
    ForegroundVisited = rgb "secondary";
    ForegroundNegative = rgb "urgent";
    ForegroundNeutral = rgb "warning";
    ForegroundPositive = rgb "sage";
    DecorationFocus = rgb "accent";
    DecorationHover = rgb "secondary";
  };
in
{
  # Expose the same palette to the system greeter without copying color values.
  options.catCafe.colors = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    internal = true;
    default = lib.mapAttrs (name: _: hex name) palette;
  };

  config = {
    _module.args.desktopTheme = {
      inherit hex rgb;
      raw = name: lib.removePrefix "#" (hex name);
    };

    wayland.windowManager.sway.config.colors =
      let
        state = border: background: text: {
          border = hex border;
          background = hex background;
          text = hex text;
          indicator = hex border;
          childBorder = hex border;
        };
      in {
        background = hex "mantle";
        focused = state "accent" "surface" "text";
        focusedInactive = state "secondary" "surface" "muted";
        unfocused = state "overlay" "base" "muted";
        urgent = state "urgent" "urgent" "base";
        placeholder = state "overlay" "mantle" "muted";
      };

    home.packages = [ pkgs.qt6Packages.qt6ct ];

    home.pointerCursor = {
      enable = true;
      gtk.enable = true;
      sway.enable = true;
      x11.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    gtk = {
      enable = true;
      theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
      inherit iconTheme;
      gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
      gtk3.extraCss = gtkCss;
      gtk4.extraCss = gtkCss + ":root {\n" + lib.concatStrings (lib.mapAttrsToList
        (name: color: "  --${lib.replaceStrings [ "_" ] [ "-" ] name}: ${hex color};\n")
        gtkColors) + "}\n";
    };
    dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

    programs.fuzzel.settings.main.icon-theme = iconTheme.name;
    # Mako does not follow theme inheritance, so include Papirus explicitly.
    services.mako.settings.icon-path = lib.concatStringsSep ":" [
      "${iconTheme.package}/share/icons/${iconTheme.name}"
      "${iconTheme.package}/share/icons/Papirus"
    ];

    programs.kitty = {
      enable = true;
      settings = {
        foreground = hex "text";
        background = hex "base";
        cursor = hex "text";
        selection_foreground = hex "base";
        selection_background = hex "text";
        background_opacity = "0.82";
        color0 = hex "surface";
        color1 = hex "urgent";
        color2 = hex "sage";
        color3 = hex "warning";
        color4 = hex "ansiBlue";
        color5 = hex "ansiMagenta";
        color6 = hex "ansiCyan";
        color7 = hex "text";
        color8 = hex "brightBlack";
        color9 = hex "brightRed";
        color10 = hex "brightGreen";
        color11 = hex "brightYellow";
        color12 = hex "brightBlue";
        color13 = hex "brightMagenta";
        color14 = hex "brightCyan";
        color15 = hex "brightWhite";
      };
    };

    xdg.configFile."qt6ct/qt6ct.conf".text = ''
      [Appearance]
      color_scheme_path=${qtPalette}
      custom_palette=true
      icon_theme=${iconTheme.name}
      standard_dialogs=default
      style=Fusion

      [Fonts]
      fixed="monospace,9,-1,2,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
      general="Sans Serif,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

      [Interface]
      activate_item_on_single_click=1
      buttonbox_layout=0
      cursor_flash_time=1000
      dialog_buttons_have_icons=1
      double_click_interval=400
      keyboard_scheme=2
      menus_have_icons=true
      show_shortcuts_in_context_menus=true
      toolbutton_style=4
      underline_shortcut=1
      wheel_scroll_lines=3

      [Troubleshooting]
      force_raster_widgets=1
    '';

    # The inspected live kdeglobals contains only generated colors, no app settings.
    xdg.configFile."kdeglobals".text = lib.generators.toINI { } {
      Icons.Theme = iconTheme.name;
      KDE.contrast = 4;
      "Colors:Window" = kdeColors "base";
      "Colors:View" = kdeColors "mantle";
      "Colors:Button" = kdeColors "surface";
      "Colors:Tooltip" = kdeColors "surface";
      "Colors:Complementary" = kdeColors "mantle";
      "Colors:Header" = kdeColors "surface";
      "Colors:Selection" = (kdeColors "accent") // {
        ForegroundNormal = rgb "base";
        ForegroundActive = rgb "base";
        ForegroundInactive = rgb "base";
      };
      WM = {
        activeBackground = rgb "surface";
        activeForeground = rgb "text";
        inactiveBackground = rgb "base";
        inactiveForeground = rgb "muted";
      };
    };

    # Alacritty is not installed or launched by this configuration. Its only live
    # setting was a generated theme import; neutralize that without installing it.
    xdg.configFile."alacritty/alacritty.toml".text = "# Use Alacritty defaults if installed manually.\n";
  };
}
