{ ... }:

{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;

    extraSessionCommands = ''
      export SWAY_UNSUPPORTED_GPU=true
    '';
  };
}
