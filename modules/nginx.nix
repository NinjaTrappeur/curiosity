{ config, lib, pkgs, ... }:
{
  services.nginx = {
    enable = true;
    virtualHosts."smartcoop.app" = {
      # forceSSL = true;
      # enableACME = true;
      locations = {
        "/".proxyPass = "http://127.0.0.1:9000";
      };
    };
  };

  # security.acme.acceptTerms = true;
  # security.acme.certs = {
  #   "smartcoop.app".email = "noteed@gmail.com";
  # };
}
