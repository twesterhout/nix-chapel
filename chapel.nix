{ stdenv
, clangStdenv
, clang
, llvmPackages
, lib
, fetchFromGitHub
, python39
, bash
, gnustep
, which
}:

llvmPackages.stdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.29.0";

  src = ./chapel;
  # fetchFromGitHub {
  #   owner = "chapel-lang";
  #   repo = "chapel";
  #   rev = "1.29.0";
  #   sha256 = "sha256-46JMbZUDjVVEdxL5uHMG3XIoUzpZMzjTX4KEKEbBsm0=";
  # };

  configurePhase = ''
    export CHPL_LLVM=system
    export CHPL_HOST_COMPILER=llvm
    export CHPL_HOST_CC=$(which clang)
    export CHPL_HOST_CXX=$(which clang++)

    export CHPL_TARGET_CPU=
    export PREFIX=$out

    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    ./configure --prefix=$out
  '';

  buildPhase = ''
    make -j
  '';

  buildInputs = [
    llvmPackages.clang
    llvmPackages.llvm
    llvmPackages.libclang.dev
  ];

  nativeBuildInputs = [
    bash
    which
    python39
    gnustep.make
    llvmPackages.clang
  ];

  meta = with lib; {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
