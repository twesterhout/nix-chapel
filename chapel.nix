{ llvmPackages
, fetchFromGitHub
, python39
, bash
, gnustep
}:

llvmPackages.stdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.29.0";

  # src = ./chapel;
  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "1.29.0";
    sha256 = "sha256-46JMbZUDjVVEdxL5uHMG3XIoUzpZMzjTX4KEKEbBsm0=";
  };

  patches = [ ./llvm_config.patch ];

  configurePhase = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall

    export CHPL_LLVM=system
    export CHPL_HOST_COMPILER=llvm
    export CHPL_HOST_CC=${llvmPackages.clang}/bin/clang
    export CHPL_HOST_CXX=${llvmPackages.clang}/bin/clang++
    export CHPL_TARGET_CPU=
    ./configure --prefix=$out
  '';

  buildPhase = ''
    make -j4
  '';

  checkPhase = ''
    export PATH=$out/bin:$PATH
    make check
  '';

  doCheck = true;

  buildInputs = [
    llvmPackages.clang
    llvmPackages.llvm
    llvmPackages.libclang.dev
  ];

  nativeBuildInputs = [
    bash
    python39
    gnustep.make
    llvmPackages.clang
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
