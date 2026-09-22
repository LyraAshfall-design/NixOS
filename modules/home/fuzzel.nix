{ pkgs, ... }:

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

        prompt = "› ";
        placeholder = "Launch...";
      };

      colors = {
        background = "1e1e2ef2";
        text = "cdd6f4ff";

        prompt = "89b4faff";
        placeholder = "7f849cff";

        input = "cdd6f4ff";
        match = "89b4faff";

        selection = "313244ff";
        selection-text = "cdd6f4ff";
        selection-match = "89b4faff";

        border = "89b4faff";
      };

      border = {
        width = 2;
        radius = 10;
      };
    };
  };
}
