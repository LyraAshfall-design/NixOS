{ ... }:

{
  # QEMU/KVM management and virtual TPM support for desktop-hosted guests.
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
  };

  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  users.users.corey.extraGroups = [ "libvirtd" ];
}
