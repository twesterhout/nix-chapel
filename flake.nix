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
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      chapel = pkgs.callPackage ./chapel.nix { };
      test = pkgs.mkDerivation {
        src = ./.;
        dontConfigure = true;
        buildPhase = ''
          
        '';

      };
    in
    {
      packages.default = chapel;
      apps.default = {
        type = "app";
        program = "${chapel}/bin/chpl";
      };
      devShells.chapel = pkgs.mkShell {
        buildInputs = with pkgs; [
          llvmPackages_14.clang
          llvmPackages_14.llvm
          llvmPackages_14.libclang.dev
        ];
        nativeBuildInputs = with pkgs; [
          chapel
          bash
          python39
          gnumake
          gnum4
          which
          pkg-config
          llvmPackages_14.clang-unwrapped
          llvmPackages_14.clang-unwrapped.dev
          llvmPackages_14.clang-unwrapped.lib.lib
        ];
        shellHook = ''
          export CLANG_UNWRAPPED=${pkgs.llvmPackages_14.clang-unwrapped}
          export CLANG_UNWRAPPED_DEV=${pkgs.llvmPackages_14.clang-unwrapped.dev}

          export EXTRA_FLAGS='-I ${pkgs.llvmPackages_14.bintools.libc.dev}/include -I ${pkgs.llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include'
        '';
      };
      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_14.stdenv; }) {
        packages = [ chapel ];
        buildInputs = with pkgs; [
          llvmPackages_14.clang
          llvmPackages_14.llvm
          llvmPackages_14.libclang.dev
          libunwind
        ];
        nativeBuildInputs = with pkgs; [
          bash
          python39
          gnumake
          gnum4
          which
          cmake
          pkg-config
          clang_14
          llvmPackages_14.clang-unwrapped
          llvmPackages_14.clang-unwrapped.dev
          llvmPackages_14.clang-unwrapped.lib.lib
          nil
          nixpkgs-fmt
        ];
        shellHook = ''
          patchShebangs --build chapel/configure
          patchShebangs --build chapel/util/printchplenv
          patchShebangs --build chapel/util/config/compileline
          patchShebangs --build chapel/util/test/checkChplInstall

          export CHPL_LLVM=system
          export CHPL_LLVM_CONFIG=${pkgs.llvmPackages_14.llvm.dev}/bin/llvm-config
          export CHPL_HOST_COMPILER=llvm
          export CHPL_HOST_CC=${pkgs.llvmPackages_14.clang}/bin/clang
          export CHPL_HOST_CXX=${pkgs.llvmPackages_14.clang}/bin/clang++
          export CHPL_TARGET_CPU=none
          export CHPL_TARGET_CC=${pkgs.llvmPackages_14.clang}/bin/clang
          export CHPL_TARGET_CXX=${pkgs.llvmPackages_14.clang}/bin/clang++
          export CHPL_GMP=system
          export CHPL_RE2=none

          export UNWIND_PATH=${pkgs.llvmPackages_14.libunwind}
          export XZ_PATH=${pkgs.xz}
          export XZ_PATH_DEV=${pkgs.xz.dev}
          export EXTRA_FLAGS='-I ${pkgs.llvmPackages_14.bintools.libc.dev}/include -I ${pkgs.llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include'
        '';
      };
      formatter = pkgs.nixpkgs-fmt;
    });
}
