{ nixpkgs }:
let
  queued-build-hook = nixpkgs.buildGoModule {
    pname = "queued-build-hook";
    version = "0.0";
    src = nixpkgs.fetchFromGitHub {
      owner = "nix-community";
      repo = "queued-build-hook";
      rev = "8c21c1bcd62bf488d7e1267f09ebf147a948994a";
      hash = "sha256-kk37GkFWovRwXTClPnWwChRb3ajf73HiRp8LpAfsMFg=";
    };
    vendorSha256 = "sha256-pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
  };

  # nix-eval-jobs depends on a specific
  nix-eval-jobs-nixpkgs = import (nixpkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "6992a4c3a69ab0d61d1c929d80d15b0cf4bf1404";
    hash = "sha256-xVMIdvyA3R/stDifjRjJr+xFu6NpFn8IQ3kDSpd9nAk=";
  }) { };
  nix-eval-jobs = nix-eval-jobs-nixpkgs.callPackage (
    nixpkgs.fetchFromGitHub {
      owner = "nix-community";
      repo = "nix-eval-jobs";
      rev = "v2.13.0";
      hash = "sha256-O0Ro9vwf2kDhGFs32puQIeW/rSSduC9sD5zV8e/GtvA=";
    }
  ) { nix = nix-eval-jobs-nixpkgs.nixUnstable; };
in {
  inherit (nixpkgs) systemfd;
  inherit queued-build-hook nix-eval-jobs;
  queue-to-post-build-hook-daemon = nixpkgs.writeShellApplication {
    name = "queue-to-post-build-hook-daemon";
    runtimeInputs = [
      queued-build-hook
    ];
    text = ''
      queued-build-hook queue -socket /tmp/queued-build-hook.sock
    '';
  };

  build-curiosity = nixpkgs.writeShellApplication {
    name = "build-curiosity";
    runtimeInputs = [
      nix-eval-jobs
    ];
    text = builtins.readFile ./build-curiosity.sh;
  };
}
