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
  nix-build-uncached = import (nixpkgs.fetchFromGitHub {
    owner = "mic92";
    repo = "nix-build-uncached";
    rev = "4fb3575a3ced5486a0c397cd4591189d1923f001";
    hash = "sha256-dJ8QxwvuHMfP/D4NSDEk5UwULSbeySRVj7MO7ElFEbg=";
  }) { };
in {
  inherit (nixpkgs) systemfd;
  inherit queued-build-hook nix-build-uncached;
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
      nix-build-uncached
    ];
    text = builtins.readFile ./build-curiosity.sh;
  };
}
