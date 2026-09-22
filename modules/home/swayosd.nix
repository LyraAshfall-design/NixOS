{ pkgs, desktopTheme, ... }:

{
  # Keep the packaged geometry and opacity; override only its colors.
  xdg.configFile."swayosd/style.css".text = ''
    @import url("${pkgs.swayosd}/etc/xdg/swayosd/style.css");
    window#osd {
      background: alpha(${desktopTheme.hex "base"}, 0.8);
    }
    window#osd image, window#osd label {
      color: ${desktopTheme.hex "text"};
    }
    window#osd trough, window#osd segment {
      background: alpha(${desktopTheme.hex "muted"}, 0.5);
    }
    window#osd progress, window#osd segment.active {
      background: ${desktopTheme.hex "accent"};
    }
  '';

  services.swayosd = {
    enable = true;
    topMargin = 0.85;
  };
}
