{ ... }:

{
  programs.swaylock = {
    enable = true;

    settings = {
      color = "1e1e2e";

      font = "sans-serif";
      font-size = 24;

      indicator-radius = 100;
      indicator-thickness = 8;

      inside-color = "313244";
      ring-color = "89b4fa";

      key-hl-color = "a6e3a1";
      bs-hl-color = "f38ba8";

      text-color = "cdd6f4";

      line-color = "00000000";
      separator-color = "00000000";

      show-failed-attempts = true;
      ignore-empty-password = true;
    };
  };
}
