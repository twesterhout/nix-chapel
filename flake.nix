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
      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages_14.stdenv; }) {
        buildInputs = with pkgs; [
          llvmPackages_14.clang
          llvmPackages_14.llvm
          llvmPackages_14.libclang.dev
        ];
        nativeBuildInputs = with pkgs; [
          bash
          python39
          gnustep.make
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
          export CHPL_HOST_COMPILER=llvm
          export CHPL_HOST_CC=${pkgs.clang_14}/bin/clang
          export CHPL_HOST_CXX=${pkgs.clang_14}/bin/clang++
          export EXTRA_FLAGS='-I ${pkgs.llvmPackages_14.bintools.libc.dev}/include -I ${pkgs.llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include'
        '';
      };
      formatter = pkgs.nixpkgs-fmt;
    });
}
