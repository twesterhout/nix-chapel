{ llvmPackages_14
, gmp
, re2
, fetchFromGitHub
, python39
, bash
, gnumake
, gnum4
, cmake
, makeWrapper
}:

llvmPackages_14.stdenv.mkDerivation {
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
    export CHPL_GMP=system
    export CHPL_RE2=none # system
    export CHPL_HOST_COMPILER=llvm
    export CHPL_HOST_CC=${llvmPackages_14.clang}/bin/clang
    export CHPL_HOST_CXX=${llvmPackages_14.clang}/bin/clang++
    export CHPL_TARGET_CPU=
    ./configure --prefix=$out
  '';

  buildPhase = ''
    make -j
  '';

  postInstall = ''
    wrapProgram $out/bin/chpl \
      --add-flags "-I ${llvmPackages_14.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include"
  '';

  # checkPhase = ''
  #   export PATH=$out/bin:$PATH
  #   make check
  # '';

  # doCheck = true;

  buildInputs = [
    llvmPackages_14.clang
    llvmPackages_14.llvm
    llvmPackages_14.libclang.dev
    gmp
    re2
  ];

  nativeBuildInputs = [
    bash
    python39
    gnumake
    gnum4
    cmake
    llvmPackages_14.clang
    makeWrapper
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
