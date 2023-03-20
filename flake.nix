{
  description = "twesterhout/nix-chapel: Nixifying Chapel";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    # extra-substituters = "https://halide-haskell.cachix.org";
    # extra-trusted-public-keys = "halide-haskell.cachix.org-1:cFPqtShCsH4aNjn2q4PHb39Omtd/FWRhrkTBcSrtNKQ=";
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
    in
    {
      packages.default = chapel;
      apps.default = {
        type = "app";
        program = "${chapel}/bin/chpl";
      };
      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_14.stdenv; }) {
        buildInputs = with pkgs; [
          llvmPackages_14.clang
          llvmPackages_14.llvm
          llvmPackages_14.libclang.dev
        ];
        nativeBuildInputs = with pkgs; [
          bash
          python39
          gnumake
          gnum4
          which
          cmake
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

          CHPL_GMP=system CHPL_TARGET_CPU=none CHPL_HOST_COMPILER=llvm CHPL_LLVM=system CHPL_LLVM_CONFIG=/nix/store/f1l9dlzsrjxangh9d2l0i3mjkyrkk3r6-llvm-14.0.6-dev/bin/llvm-config CHPL_RE2=none CHPL_HOST_COMPILER=llvm CHPL_HOST_CC=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang CHPL_HOST_CXX=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang++ CHPL_TARGET_CC=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang CHPL_TARGET_CXX=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang++ ./prefix/share/chapel/1.30/util/printchplenv
          export EXTRA_FLAGS='-I ${pkgs.llvmPackages_14.bintools.libc.dev}/include -I ${pkgs.llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include'
        '';
      };
      formatter = pkgs.nixpkgs-fmt;
    });
}
