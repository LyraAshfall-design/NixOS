{ pkgs, desktopTheme, ... }:

{
  programs.fuzzel = {
    enable = true;

    settings = {
      main = {
        terminal = "${pkgs.kitty}/bin/kitty";

        layer = "overlay";

        font = "sans-serif:size=13";

        width = 48;
        lines = 10;

        horizontal-pad = 18;
        vertical-pad = 14;
        inner-pad = 10;

        prompt = "ฅ ";
        placeholder = "Launch...";
      };

      colors = {
        background = "${desktopTheme.raw "base"}f2";
        text = "${desktopTheme.raw "text"}ff";

        prompt = "${desktopTheme.raw "accent"}ff";
        placeholder = "${desktopTheme.raw "muted"}ff";

        input = "${desktopTheme.raw "text"}ff";
        match = "${desktopTheme.raw "accent"}ff";

        selection = "${desktopTheme.raw "accent"}ff";
        selection-text = "${desktopTheme.raw "base"}ff";
        selection-match = "${desktopTheme.raw "surface"}ff";

        border = "${desktopTheme.raw "accent"}ff";
      };

      border = {
        width = 2;
        radius = 10;
      };
    };
  };
}
