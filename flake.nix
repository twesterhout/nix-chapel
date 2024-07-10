{
  description = "twesterhout/nix-chapel: Nixifying Chapel";

  nixConfig = {
    extra-substituters = "https://twesterhout-chapel.cachix.org";
    extra-trusted-public-keys = "twesterhout-chapel.cachix.org-1:bs5PQPqy21+rP2KJl+O40/eFVzdsTe6m7ZTiOEE7PaI=";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      inherit (nixpkgs) lib;

      chapel-stable = pkgs: version: hash:
        (pkgs.callPackage ./chapel.nix { }).overrideAttrs (attrs: rec {
          inherit version;
          name = "${attrs.pname}-${version}";
          src = pkgs.fetchFromGitHub {
            owner = "chapel-lang";
            repo = "chapel";
            rev = version;
            hash = hash;
          };
        });

      chapel-with-settings = drv: settings: drv.override { inherit settings; };
      chapel-with-compiler-settings = drv: compiler: settings: drv.override { inherit compiler settings; };

      single-locale-variants = pkgs: drv:
        (map (chapel-with-settings drv) (lib.cartesianProductOfSets {
          CHPL_LIB_PIC = [ "none" "pic" ];
          CHPL_TARGET_CPU = [ "none" ] ++ lib.optional pkgs.stdenv.isx86_64 "nehalem";
        }))
        ++ [
          # The following are great for debugging
          # Currently broken on Chapel main
          (chapel-with-compiler-settings drv "gnu" { CHPL_TARGET_MEM = "cstdlib"; CHPL_HOST_MEM = "cstdlib"; CHPL_UNWIND = "none"; CHPL_TASKS = "fifo"; CHPL_SANITIZE_EXE = "address"; CHPL_LIB_PIC = "none"; })
          (chapel-with-compiler-settings drv "gnu" { CHPL_TARGET_MEM = "cstdlib"; CHPL_HOST_MEM = "cstdlib"; CHPL_UNWIND = "none"; CHPL_TASKS = "fifo"; CHPL_SANITIZE_EXE = "address"; CHPL_LIB_PIC = "pic"; })
        ];

      multi-locale-variants = pkgs: drv:
        # GASNet-based
        (map (chapel-with-settings drv) (lib.cartesianProductOfSets {
          CHPL_TARGET_CPU = [ "none" ] ++ lib.optional pkgs.stdenv.isx86_64 "nehalem";
          CHPL_COMM = [ "gasnet" ];
          CHPL_COMM_SUBSTRATE = [ "smp" "udp" "ibv" ];
        }));

      chapel-overlay = final: prev: {
        chapel = final.callPackage ./chapel.nix { };
        chapel-gnu = final.callPackage ./chapel.nix { compiler = "gnu"; };
        chapel_2_0 = chapel-stable final "2.0.1" "sha256-BRUjWyngAg1bNXwpOFIkd/CggJKzrw9ugRwy95QHdOQ=";
        chapel_2_1 = chapel-stable final "2.1.0" "sha256-uMcaH8ruElHzUcbPSjrh/QsKr7rncGTsHVdg1mNlu5E=";
      };

      # examples-overlay = final: prev: {
      #   chapelExamples =
      #     let
      #       hello-with-flags = pname: settings: final.stdenv.mkDerivation {
      #         inherit pname;
      #         version = "1.0.0";
      #         src = ./src;
      #         nativeBuildInputs = with prev; [
      #           (chapel.override { customSettings = settings; })
      #         ];
      #         buildPhase = ''
      #           mkdir -p $out/bin
      #           chpl -o $out/bin/hello hello6-taskpar-dist.chpl
      #           for f in $(ls $out/bin);
      #             chapelFixupBinary $out/bin/$f
      #           done
      #         '';
      #       };
      #     in
      #     (prev.chapelExamples or { }) // rec {
      #       hello = hello-with-flags "hello" {
      #         CHPL_COMM = "none";
      #       };
      #       hello-smp = hello-with-flags "hello-smp" {
      #         CHPL_COMM = "gasnet";
      #         CHPL_COMM_SUBSTRATE = "smp";
      #         CHPL_LAUNCHER = "none";
      #       };
      #       hello-ibv = hello-with-flags "hello-ibv" {
      #         CHPL_COMM = "gasnet";
      #         CHPL_COMM_SUBSTRATE = "ibv";
      #         CHPL_LAUNCHER = "none";
      #       };
      #       hello-ibv-singularity = prev.singularity-tools.buildImage {
      #         name = "hello-ibv-singularity";
      #         contents = [ hello-ibv ];
      #         runScript = "${hello-ibv}/bin/hello $@";
      #         diskSize = 10240;
      #         memSize = 5120;
      #       };
      #     };
      # };

      pkgs-for = system: import nixpkgs {
        inherit system;
        overlays = [
          chapel-overlay
          # examples-overlay 
        ];
      };
    in
    {
      packages = flake-utils.lib.eachDefaultSystemMap (system:
        let pkgs = pkgs-for system; in {
          inherit (pkgs) chapel chapel_2_0 chapel_2_1;
          default = pkgs.chapel;

          hm = (chapel-with-compiler-settings pkgs.chapel "gnu" { CHPL_TARGET_MEM = "cstdlib"; CHPL_HOST_MEM = "cstdlib"; CHPL_UNWIND = "none"; CHPL_TASKS = "fifo"; CHPL_SANITIZE_EXE = "address"; CHPL_LIB_PIC = "none"; });

          all = pkgs.linkFarm "nix-chapel-all" (lib.lists.imap0 (i: x: { name = toString i; path = x; }) ([
            # Add more configurations here

          ]
          ++ (single-locale-variants pkgs pkgs.chapel_2_0)
          ++ (multi-locale-variants pkgs pkgs.chapel_2_0)
          ++ (single-locale-variants pkgs pkgs.chapel_2_1)
          ++ (multi-locale-variants pkgs pkgs.chapel_2_1)
          ++ (single-locale-variants pkgs pkgs.chapel)
          ++ (multi-locale-variants pkgs pkgs.chapel)
          ));
        });

      apps = flake-utils.lib.eachDefaultSystemMap
        (system: with (pkgs-for system); {
          default = {
            type = "app";
            program = "${chapel}/bin/chpl";
          };
        });

      overlays = {
        default = chapel-overlay;
        chapel = chapel-overlay;
        # examples = examples-overlay;
      };

      # devShells = flake-utils.lib.eachDefaultSystemMap
      #   (system: with (pkgs-for system);
      #   let
      #     chapel-with-compiler-settings = compiler: settings: chapel.override { inherit compiler settings; };
      #   in
      #   {
      #     default = mkShell {
      #       nativeBuildInputs = [
      #         (chapel-with-compiler-settings "gnu" {
      #           CHPL_COMM = "none";
      #           # CHPL_COMM_SUBSTRATE = "smp";
      #           # CHPL_LAUNCHER = "none";
      #           CHPL_LIB_PIC = "pic";
      #           # CHPL_UNWIND = "none";
      #           # CHPL_TASKS = "fifo";
      #           CHPL_RE2 = "none";
      #         })
      #         (python3.withPackages (ps: with ps; [ cffi numpy cython ]))
      #       ];
      #     };
      #   });
    };
}
