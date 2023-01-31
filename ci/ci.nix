let pkgs = (import ../default.nix).nixpkgs;
in (pkgs.enableDebugging (pkgs.hello.overrideAttrs (prev: { separateDebugInfo = true; }))).debug
