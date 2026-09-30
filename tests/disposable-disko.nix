# Explicit test expression only; never imported by either production host.
{ snapshot, device }:
let
  flake = builtins.getFlake snapshot;
  production = flake.nixosConfigurations.nixos-desktop;
  expected = "/dev/disk/by-id/nvme-SIX_X7400_SSD_STX26012100037853";
  test = production.extendModules {
    modules = [
      ({ lib, ... }: {
        # The entire desktop layout is inherited; only its whole disk changes.
        disko.devices.disk.main.device = lib.mkForce device;
      })
    ];
  };
in
assert production.config.disko.devices.disk.main.device == expected;
# Runtime identity/busy checks belong to setup. This expression is not an
# alternate production installer and deliberately also rejects the known SSD node.
assert builtins.match "/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)" device != null;
assert device != "/dev/nvme0n1";
{
  config = test.config;
  script = test.config.system.build.destroyFormatMount;
}
