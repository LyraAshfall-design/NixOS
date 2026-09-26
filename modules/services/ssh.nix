{ ... }:

{
  # Hosts choose their own network exposure and authorized public keys.
  services.openssh = {
    enable = true;
    openFirewall = false;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      AuthenticationMethods = "publickey";
    };
  };
}
