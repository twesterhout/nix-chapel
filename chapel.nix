{ llvmPackages_14
, gmp
, re2
, fetchFromGitHub
, python39
, bash
, gnumake
, gnum4
, which
, cmake
, makeWrapper
}:

llvmPackages_14.stdenv.mkDerivation {
  pname = "chapel";
  version = "1.30.0";

  # src = ./chapel;
  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "a5d4cf00ac813be8e77203bcdd76aea7bddff940";
    sha256 = "sha256-uh2HFx8R8/fIWwaKOnkpLza+Q+AaXoBNnVPaVblZ7oM=";
  };

  patches = [ ./llvm-and-clang-paths.patch ];

  configurePhase = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall

    export CHPL_LLVM=system
    export CHPL_LLVM_CONFIG=${llvmPackages_14.llvm.dev}/bin/llvm-config
    export CHPL_HOST_COMPILER=llvm
    export CHPL_HOST_CC=${llvmPackages_14.clang}/bin/clang
    export CHPL_HOST_CXX=${llvmPackages_14.clang}/bin/clang++
    export CHPL_TARGET_CPU=none
    export CHPL_TARGET_CC=${llvmPackages_14.clang}/bin/clang
    export CHPL_TARGET_CXX=${llvmPackages_14.clang}/bin/clang++
    export CHPL_GMP=system
    export CHPL_RE2=none

    # CHPL_GMP=system CHPL_TARGET_CPU=none CHPL_HOST_COMPILER=llvm CHPL_LLVM=system CHPL_LLVM_CONFIG=/nix/store/f1l9dlzsrjxangh9d2l0i3mjkyrkk3r6-llvm-14.0.6-dev/bin/llvm-config CHPL_RE2=none CHPL_HOST_COMPILER=llvm CHPL_HOST_CC=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang CHPL_HOST_CXX=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang++ CHPL_TARGET_CC=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang CHPL_TARGET_CXX=/nix/store/2qcas2wxgc38krmdbnhljgmndizxahvm-clang-wrapper-14.0.6/bin/clang++ ./prefix/share/chapel/1.30/util/printchplenv
    ./configure --prefix=$out
  '';

  buildPhase = ''
    make -j
  '';

  postInstall = ''
    wrapProgram $out/bin/chpl \
      --set-default CHPL_LLVM system \
      --set-default CHPL_LLVM_CONFIG "${llvmPackages_14.llvm.dev}/bin/llvm-config" \
      --set-default CHPL_HOST_COMPILER llvm \
      --set-default CHPL_HOST_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_HOST_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_TARGET_CPU none \
      --set-default CHPL_TARGET_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_TARGET_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_GMP system \
      --set-default CHPL_RE2 none \
      --add-flags "-I ${llvmPackages_14.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include" \
      --add-flags "-L ${gmp}/lib"

    substituteInPlace $out/share/chapel/1.30/util/printchplenv \
      --replace '`"$CWD/config/find-python.sh"`' '${python39}/bin/python'
  '';

  checkPhase = ''
    # export PATH=$out/bin:$PATH
    # make check
    echo "==== START checkPhase ===="
    # ls -l
    # find . -type f -name "chpl"
    export PATH=$PWD/bin/linux64-x86_64:$PATH
    wrapProgram bin/linux64-x86_64/chpl \
      --add-flags "-I ${llvmPackages_14.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include" \
      --add-flags "-L ${gmp}/lib"
    echo "==== invoking make check ===="
    make check
    echo "==== undoing wrapProgra ===="
    mv bin/linux64-x86_64/.chpl-wrapped bin/linux64-x86_64/chpl
    echo "==== END checkPhase ===="
  '';

  doCheck = true;

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
    which
    cmake
    llvmPackages_14.clang
    makeWrapper
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
