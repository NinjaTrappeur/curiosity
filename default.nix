let
  sources = import ./nix/sources.nix;
  nixpkgs = import sources.nixpkgs { inherit overlays; };
  overlays = import ./nix/overlays.nix;

  os = import "${toString sources.nixpkgs}/nixos/lib/eval-config.nix" {
    modules = [
      ./machine/configuration.nix
      "${toString sources.nixpkgs}/nixos/modules/virtualisation/digital-ocean-image.nix"
      ./machine/disk-size.nix
      ./machine/https.nix
      ./modules/play.nix
    ];
  };

  qemu = import "${toString sources.nixpkgs}/nixos/lib/eval-config.nix" {
    modules = [
      ./machine/configuration.nix
      "${toString sources.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
      ./machine/no-gui.nix
    ];
  };
    binaries = nixpkgs.haskellPackages.curiosity;
    content = (import ./content { inherit nixpkgs; }).html.all;
    data = (import ./content { inherit nixpkgs; }).data;
    indexes = (import ./content { inherit nixpkgs; }).indexes;
    asciinema = (import ./content { inherit nixpkgs; }).asciinema;
    scenarios = (import ./content { inherit nixpkgs; }).scenarios;
    haddock = nixpkgs.haskellPackages.curiosity.doc;
    run = import ./scripts/integration-tests {
      inherit nixpkgs binaries haddock content data scenarios;
    };
    ci-tools = import ./ci { inherit nixpkgs; };
in rec
  {
    # Build with nix-build -A <attr>
    # binaries + haddock are also available as binaries.all.
    inherit nixpkgs binaries content data indexes asciinema scenarios haddock run;
    inherit (run) run-vm-tests;
    inherit ci-tools;
    public = (import ./content { inherit nixpkgs; }).html.public;
    static = (import "${sources.smart-design-hs}").static;
    man-pages = (import ./man { inherit nixpkgs; }).man-pages;
    toplevel = os.config.system.build.toplevel;
    image = os.config.system.build.digitalOceanImage;
    runvm = qemu.config.system.build.vm;
    runenv = run.run-full-environment;
    run-vm-tests-interactive = run-vm-tests.driverInteractive;
    docker = (import ./docker { inherit nixpkgs; });

    # A shell to try out our binaries
    # TODO Can this be defined in shell.nix instead ?
    # Run with nix-shell default.nix -A shell
    shell = nixpkgs.mkShell {
      buildInputs = [
        binaries
        man-pages # This works in environment.systemPackages but here we need
                  # to set MANPATH below.
                  # I guess it would work if it was packaged with the binaries.
        run.run-full-environment
        run.run-nginx
      ];
      # Setting the CURIOSITY_STATIC_DIR, CURIOSITY_DATA_DIR, and
      # CURIOSITY_SCENARIOS_DIR is not strictly necessary as this shell is
      # usually run from the source repository, and the default paths will work
      # (provided the _site/ directory has been built. But this makes the shell
      # usable even without those conditions.
      shellHook = ''
        source <(cty             --bash-completion-script `which cty`)
        export CURIOSITY_STATIC_DIR=${content}
        export CURIOSITY_DATA_DIR=${data}
        export CURIOSITY_SCENARIOS_DIR=${scenarios}
        export MANPATH=${man-pages}/share/man
      '';
    };
  }
