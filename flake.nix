{
  description = "twesterhout/nix-chapel: Nixifying Chapel";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    extra-substituters = "https://twesterhout-chapel.cachix.org";
    extra-trusted-public-keys = "twesterhout-chapel.cachix.org-1:bs5PQPqy21+rP2KJl+O40/eFVzdsTe6m7ZTiOEE7PaI=";
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    with builtins;
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      chapel = pkgs.callPackage ./chapel.nix { };
      chapelFixupBinary = with pkgs; writeShellScriptBin "chapelFixupBinary" ''
        set -e

        replaceReferencesWith() {
          sed -i "s:$2:$3:g" "$1"
        }

        hideReferencesTo() {
          declare -r filepath=$1
          declare -r original=$2
          declare -r new=$(echo "$original" | sed -E 's:/nix/store/[a-z0-9]{32}-:/nix/store/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-:')
          replaceReferencesWith "$filepath" "$original" "$new"
        }

        if [ $# -ne 1 ]; then
          echo "Expected a single argument -- binary to fixup"
          exit 1
        fi

        binaryFile=$1
        hideReferencesTo "$binaryFile" ${llvmPackages_14.clang}
        hideReferencesTo "$binaryFile" ${llvmPackages_14.clang-unwrapped.lib}
        hideReferencesTo "$binaryFile" ${llvmPackages_14.llvm.dev}
        hideReferencesTo "$binaryFile" ${llvmPackages_14.bintools.libc.dev}
        replaceReferencesWith "$binaryFile" ${chapel}/third-party/ ${chapel.third_party}/
        hideReferencesTo "$binaryFile" ${chapel}
      '';

      hello-chapel = pkgs.stdenv.mkDerivation {
        name = "hello-chapel";
        version = "1.0.0";
        src = inputs.nix-filter.lib {
          root = ./.;
          include = [ (inputs.nix-filter.lib.matchExt "chpl") ];
        };
        dontConfigure = true;
        nativeBuildInputs = [ chapel chapelFixupBinary pkgs.coreutils ];
        # disallowedReferences = [ pkgs.llvmPackages_14.clang ];
        buildPhase = ''
          chpl --print-commands --devel hello6-taskpar-dist.chpl
          chapelFixupBinary hello6-taskpar-dist
        '';
        installPhase = ''
          mkdir -p $out/bin
          cp -v hello6-taskpar-dist $out/bin/
        '';
      };

      hello-docker = pkgs.dockerTools.buildImage {
        name = "hello-docker";
        tag = "latest";
        config = {
          Entrypoint = [ "${hello-chapel}/bin/hello6-taskpar-dist" ];
        };
      };

      hello-singularity = pkgs.singularity-tools.buildImage {
        name = "hello-singularity";
        contents = [ hello-chapel ];
        runScript = ''
          #!${pkgs.stdenv.shell}

          export PATH=${hello-chapel}/bin:$PATH
          exec /bin/sh
        '';
        diskSize = 10240;
        memSize = 5120;
      };
    in
    {
      packages.default = chapel;
      packages.chapel = chapel;
      packages.chapelFixupBinary = chapelFixupBinary;
      packages.hello-chapel = hello-chapel;
      packages.hello-docker = hello-docker;
      packages.hello-singularity = hello-singularity;
      apps.default = {
        type = "app";
        program = "${chapel}/bin/chpl";
      };

      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_14.stdenv; }) {
        packages = [ chapel ];
        buildInputs = with pkgs; [
          llvmPackages_14.clang
          llvmPackages_14.llvm
          llvmPackages_14.libclang.dev
          libunwind
          gmp
          mpi
          pmix
          rdma-core
        ];
        nativeBuildInputs = with pkgs; [
          bash
          cmake
          gnumake
          gnum4
          file
          llvmPackages_14.clang
          makeWrapper
          perl
          pkg-config
          python39
          which
        ];
        shellHook = with pkgs; ''
          export CC=${llvmPackages_14.clang}/bin/cc
          export CXX=${llvmPackages_14.clang}/bin/c++
          export CHPL_LLVM=system
          export CHPL_LLVM_CONFIG=${llvmPackages_14.llvm.dev}/bin/llvm-config
          export CHPL_HOST_COMPILER=llvm
          export CHPL_HOST_CC=${llvmPackages_14.clang}/bin/clang
          export CHPL_HOST_CXX=${llvmPackages_14.clang}/bin/clang++
          export CHPL_TARGET_CPU=none
          export CHPL_TARGET_CC=${llvmPackages_14.clang}/bin/clang
          export CHPL_TARGET_CXX=${llvmPackages_14.clang}/bin/clang++
          export CHPL_GMP=system
          export CHPL_RE2=bundled
          export CHPL_UNWIND=system
        '';
      };
      formatter = pkgs.nixpkgs-fmt;
    });
}
