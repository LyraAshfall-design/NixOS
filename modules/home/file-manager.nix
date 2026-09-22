{ ... }:

{
  # Yazi remains the terminal file manager; Thunar owns graphical folder opens.
  programs.yazi.enable = true;
  # Desktop-specific MIME defaults preserve the existing unmanaged mimeapps.list
  # (currently Vesktop's Discord protocol association) without an activation clash.
  xdg.configFile."sway-mimeapps.list".text = ''
    [Default Applications]
    inode/directory=thunar.desktop;
  '';
}
