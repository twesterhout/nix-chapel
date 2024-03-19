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

      chapel-stable = pkgs: version: hash:
        (pkgs.callPackage ./chapel.nix { llvmPackages = pkgs.llvmPackages_15; }).overrideAttrs (attrs: rec {
          inherit version;
          name = "${attrs.pname}-${version}";
          src = pkgs.fetchFromGitHub {
            owner = "chapel-lang";
            repo = "chapel";
            rev = version;
            hash = hash;
          };
        });

      chapel-overlay = final: prev: rec {
        chapel = final.callPackage ./chapel.nix { llvmPackages = final.llvmPackages_16; };
        chapel-gnu = final.callPackage ./chapel.nix { llvmPackages = final.llvmPackages_16; compiler = "gnu"; };

        chapel_1_33 = chapel-stable final "1.33.0" "";
        chapel_1_31 = chapel-stable final "1.31.0" "sha256-/yH3NYPP1JaqJWjYADoFjq2djYbZ4ywuHtMIPnZfyBA=";

        pr_XXX = chapel.overrideAttrs (attrs: {
          # https://github.com/chapel-lang/chapel/pull/24323
          patches = (attrs.patches or [ ]) ++ [
            (final.fetchpatch {
              name = "openStringFile.patch";
              url = "https://github.com/jeremiah-corrado/chapel/commit/30f63ae36497639ab2e3ba3d46888c314bca1949.patch";
              hash = "sha256-ElcOJXTF8rbk5b3WS+67dpGlgXjqz2xYoYyMqYArbzI=";
            })
          ];
          # src = final.fetchFromGitHub {
          #   owner = "jeremiah-corrado";
          #   repo = "chapel";
          #   rev = "30f63ae36497639ab2e3ba3d46888c314bca1949";
          #   hash = "sha256-jlv8lbQpKJg01rh+Ae2+LHelmdNmzhrilfSIyP7PCeU=";
          # };
        });
      };

      examples-overlay = final: prev: {
        chapelExamples =
          let
            hello-with-flags = pname: settings: final.stdenv.mkDerivation {
              inherit pname;
              version = "1.0.0";
              src = ./src;
              nativeBuildInputs = with prev; [
                (chapel.override { customSettings = settings; })
              ];
              buildPhase = ''
                mkdir -p $out/bin
                chpl -o $out/bin/hello hello6-taskpar-dist.chpl
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
      packages = flake-utils.lib.eachDefaultSystemMap (system: with (pkgs-for system);
        let
          chapel-with-settings = settings: chapel.override { inherit settings; };
          chapel-with-compiler-settings = compiler: settings: chapel.override { inherit compiler settings; };

          # A hack to make 'nix build' build multiple derivations at once.
          combine = drvs: stdenv.mkDerivation {
            pname = "combine";
            version = "0.1";
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/share
            '' + lib.concatStringsSep "\n" (builtins.map (p: "echo '${p}' >> $out/share/paths") drvs);
          };
        in
        rec {
          default = chapel;
          examples = chapelExamples;
          inherit chapel chapel_1_31 chapelFixupBinary pr_XXX;

          single-locale = combine (
            (map chapel-with-settings (lib.cartesianProductOfSets {
              CHPL_LIB_PIC = [ "none" "pic" ];
              CHPL_TARGET_CPU = [ "none" ] ++ lib.optional stdenv.isx86_64 "nehalem";
            }))
            ++ [
              # The following are great for debugging
              (chapel-with-compiler-settings "gnu" { CHPL_TARGET_MEM = "cstdlib"; CHPL_HOST_MEM = "cstdlib"; CHPL_UNWIND = "none"; CHPL_TASKS = "fifo"; CHPL_SANITIZE_EXE = "address"; CHPL_LIB_PIC = "none"; })
              (chapel-with-compiler-settings "gnu" { CHPL_TARGET_MEM = "cstdlib"; CHPL_HOST_MEM = "cstdlib"; CHPL_UNWIND = "none"; CHPL_TASKS = "fifo"; CHPL_SANITIZE_EXE = "address"; CHPL_LIB_PIC = "pic"; })
            ]
          );

          multi-locale = combine
            # GASNet-based
            (map chapel-with-settings (lib.cartesianProductOfSets {
              CHPL_TARGET_CPU = [ "none" ] ++ lib.optional stdenv.isx86_64 "nehalem";
              CHPL_COMM = [ "gasnet" ];
              CHPL_COMM_SUBSTRATE = [ "smp" "udp" "ibv" ];
            }))
          ;

          all = combine [ single-locale multi-locale ];
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
