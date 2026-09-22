{ desktopTheme, ... }:

{
  programs.swaylock = {
    enable = true;

    settings = {
      color = desktopTheme.raw "mantle";

      font = "sans-serif";
      font-size = 24;

      indicator-radius = 100;
      indicator-thickness = 8;

      inside-color = desktopTheme.raw "surface";
      ring-color = desktopTheme.raw "accent";

      key-hl-color = desktopTheme.raw "sage";
      bs-hl-color = desktopTheme.raw "urgent";

      inside-clear-color = desktopTheme.raw "surface";
      inside-ver-color = desktopTheme.raw "surface";
      inside-wrong-color = desktopTheme.raw "surface";
      ring-clear-color = desktopTheme.raw "secondary";
      ring-ver-color = desktopTheme.raw "warning";
      ring-wrong-color = desktopTheme.raw "urgent";
      text-clear-color = desktopTheme.raw "text";
      text-ver-color = desktopTheme.raw "text";
      text-wrong-color = desktopTheme.raw "text";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";

      text-color = desktopTheme.raw "text";

      line-color = "00000000";
      separator-color = "00000000";

      show-failed-attempts = true;
      ignore-empty-password = true;
    };
  };
}
