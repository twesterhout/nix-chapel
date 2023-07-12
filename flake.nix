{
  description = "twesterhout/nix-chapel: Nixifying Chapel";

  nixConfig = {
    extra-substituters = "https://twesterhout-chapel.cachix.org";
    extra-trusted-public-keys = "twesterhout-chapel.cachix.org-1:bs5PQPqy21+rP2KJl+O40/eFVzdsTe6m7ZTiOEE7PaI=";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      inherit (nixpkgs) lib;

      chapel-overlay = final: prev: {
        chapel = final.callPackage ./chapel.nix { llvmPackages = final.llvmPackages_15; };
        chapelFixupBinary = final.callPackage ./chapel-fixup-binary.nix { };
      };

      examples-overlay = final: prev: {
        chapelExamples =
          let
            hello-with-flags = pname: settings: final.stdenv.mkDerivation {
              inherit pname;
              version = "1.0.0";
              src = ./src;
              nativeBuildInputs = with prev; [ chapel chapelFixupBinary ];
              buildPhase =
                let
                  flags = lib.concatStringsSep " "
                    (lib.mapAttrsToList (name: value: "${name}=${value}") settings);
                in
                ''
                  mkdir -p $out/bin
                  ${flags} chpl -o $out/bin/hello hello6-taskpar-dist.chpl
                  for f in $(ls $out/bin);
                    chapelFixupBinary $out/bin/$f
                  done
                '';
            };
          in
          (prev.chapelExamples or { }) // rec {
            hello = hello-with-flags "hello" {
              CHPL_COMM = "none";
            };
            hello-smp = hello-with-flags "hello-smp" {
              CHPL_COMM = "gasnet";
              CHPL_COMM_SUBSTRATE = "smp";
              CHPL_LAUNCHER = "none";
            };
            hello-ibv = hello-with-flags "hello-ibv" {
              CHPL_COMM = "gasnet";
              CHPL_COMM_SUBSTRATE = "ibv";
              CHPL_LAUNCHER = "none";
            };
            hello-ibv-singularity = prev.singularity-tools.buildImage {
              name = "hello-ibv-singularity";
              contents = [ hello-ibv ];
              runScript = "${hello-ibv}/bin/hello $@";
              diskSize = 10240;
              memSize = 5120;
            };
          };
      };

      pkgs-for = system: import nixpkgs {
        inherit system;
        overlays = [ chapel-overlay examples-overlay ];
      };
    in
    {
      packages = flake-utils.lib.eachDefaultSystemMap (system: with (pkgs-for system); {
        default = chapel;
        examples = chapelExamples;
        inherit chapel chapelFixupBinary;
      });

      apps = flake-utils.lib.eachDefaultSystemMap (system: with (pkgs-for system); {
        default = {
          type = "app";
          program = "${chapel}/bin/chpl";
        };
      });

      overlays = {
        default = chapel-overlay;
        chapel = chapel-overlay;
        examples = examples-overlay;
      };

      # devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_14.stdenv; }) {
      #   packages = [ chapel ];
      #   buildInputs = with pkgs; [
      #     llvmPackages_14.clang
      #     llvmPackages_14.llvm
      #     llvmPackages_14.libclang.dev
      #     libunwind
      #     gmp
      #     mpi
      #     pmix
      #     rdma-core
      #   ];
      #   nativeBuildInputs = with pkgs; [
      #     bash
      #     cmake
      #     gnumake
      #     gnum4
      #     file
      #     llvmPackages_14.clang
      #     makeWrapper
      #     perl
      #     pkg-config
      #     python39
      #     which
      #   ];
      #   shellHook = with pkgs; ''
      #     export CC=${llvmPackages_14.clang}/bin/cc
      #     export CXX=${llvmPackages_14.clang}/bin/c++
      #     export CHPL_LLVM=system
      #     export CHPL_LLVM_CONFIG=${llvmPackages_14.llvm.dev}/bin/llvm-config
      #     export CHPL_HOST_COMPILER=llvm
      #     export CHPL_HOST_CC=${llvmPackages_14.clang}/bin/clang
      #     export CHPL_HOST_CXX=${llvmPackages_14.clang}/bin/clang++
      #     export CHPL_TARGET_CPU=none
      #     export CHPL_TARGET_CC=${llvmPackages_14.clang}/bin/clang
      #     export CHPL_TARGET_CXX=${llvmPackages_14.clang}/bin/clang++
      #     export CHPL_GMP=system
      #     export CHPL_RE2=bundled
      #     export CHPL_UNWIND=system
      #   '';
      # };
      # formatter = pkgs.nixpkgs-fmt;
    };
}
