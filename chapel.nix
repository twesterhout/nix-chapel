{ bash
, cmake
, coreutils
, fetchFromGitHub
, file
, gmp
, gnumake
, gnum4
, libunwind
, llvmPackages_14
, makeWrapper
, mpi
, perl
, pmix
, python3
, python3Packages
, pkg-config
, rdma-core
, which
, xz
}:

let
  pycparser = python3Packages.buildPythonPackage {
    pname = "pycparser";
    version = "2.20";
    src = fetchFromGitHub {
      owner = "eliben";
      repo = "pycparser";
      rev = "release_v2.20";
      sha256 = "sha256-M2Col80YezCyRpKSKBPav8HrLhfmbzLxAIpVz0ULBYg=";
    };
    doCheck = false;
  };
  pycparserext = python3Packages.buildPythonPackage {
    pname = "pycparserext";
    version = "2020.1";
    src = fetchFromGitHub {
      owner = "inducer";
      repo = "pycparserext";
      rev = "6b9db4a17130bd90a4c8e44d07f39ba9cc36c6d1";
      sha256 = "sha256-PYfYOukddeo7SN6B9GYNY2mj3S1Dhk0ONw8ycOoYPWA=";
    };
    propagatedBuildInputs = with python3Packages; [
      pycparser
      ply
    ];
  };
in
llvmPackages_14.stdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.31.0";

  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "0630fe92c5416dec8236c63f6eebc1c470b5bbc3";
    sha256 = "sha256-iHjKfBqvLnAIR2pSGsc8gm89GBgWMHzGSVfWIyQz5jg=";
  };

  outputs = [ "out" "third_party" ];

  c2chapel-fake-headers = fetchFromGitHub {
    owner = "eliben";
    repo = "pycparser";
    rev = "0055facfb5b5289ce8ef2ef12b18e34a223f9d20";
    sha256 = "sha256-M2Col80YezCyRpKSKBPav8HrLhfmbzLxAIpVz0ULBYg=";
  };

  # patches = [ ./llvm-and-clang-paths.patch ];
  postPatch = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall
    patchShebangs --build tools/c2chapel/c2chapel.py

    # In the following we set up all the dependencies for c2chapel such that
    # Chapel doesn't try (and doesn't need to) create Python virtual environments
    substituteInPlace Makefile \
      --replace 'c2chapel: third-party-c2chapel-venv FORCE' 'c2chapel: FORCE'

    # This is essentially what the $(FAKES) target in the Makefile does, but
    # we use $${c2chapel-fake-headers} instead of downloading the archive from
    # the internet
    pushd tools/c2chapel
    mkdir -p install/fakeHeaders
    cp --no-preserve=mode -r \
      ${c2chapel-fake-headers}/utils/fake_libc_include/* \
      install/fakeHeaders/
    ./utils/fixFakes.sh install/fakeHeaders utils/custom.h
    mkdir -p install/fakeHeaders/utils
    cp utils/custom.h install/fakeHeaders/utils/

    substituteInPlace Makefile \
      --replace 'c2chapel: c2chapel-venv $(FAKES)' 'c2chapel:'
    popd
  '';

  configurePhase = ''
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
    export PMI_HOME=${pmix}

    ./configure --chpl-home=$out
  '';

  buildPhase = ''
    for CHPL_LIB_PIC in none pic; do
      make CHPL_LIB_PIC=$CHPL_LIB_PIC -j
    done
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=smp -j
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp -j
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp CHPL_LAUNCHER=none -j
    # for CHPL_LAUNCHER in none gasnetrun_mpi slurm-gasnetrun_mpi slurm-srun; do
    #   make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=mpi CHPL_LAUNCHER=$CHPL_LAUNCHER -j
    # done
    for CHPL_LAUNCHER in none gasnetrun_ibv slurm-gasnetrun_ibv; do
      make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_LAUNCHER=$CHPL_LAUNCHER -j
    done
    make -j c2chapel
  '';

  postInstall = ''
    mkdir -p $third_party
    cp -v -r $out/third-party/gasnet $third_party
    find $third_party -type d -name "include" -exec rm -r {} +
    find $third_party -type d -name "lib" -exec rm -r {} +
    find $third_party -type d -name "share" -exec rm -r {} +
    find $third_party -type f -name "Makefile*" -exec rm {} +

    mkdir -p $out/tools/c2chapel
    cp tools/c2chapel/c2chapel* $out/tools/c2chapel/
    cp -r tools/c2chapel/install $out/tools/c2chapel/

    makeWrapper $out/tools/c2chapel/c2chapel.py $out/bin/c2chapel \
      --prefix PYTHONPATH : "${pycparser}/${python3.sitePackages}" \
      --prefix PYTHONPATH : "${pycparserext}/${python3.sitePackages}"

    makeWrapper $out/bin/linux64-x86_64/chpl $out/bin/chpl \
      --prefix PATH : "${pkg-config}/bin" \
      --prefix PATH : "${coreutils}/bin" \
      --prefix PATH : "${gnumake}/bin" \
      --prefix PATH : "${mpi}/bin" \
      --prefix PATH : "${python3}/bin" \
      --prefix PKG_CONFIG_PATH : "${libunwind.dev}/lib/pkgconfig" \
      --set-default CHPL_HOME $out \
      --set-default CHPL_LLVM system \
      --set-default CHPL_LLVM_CONFIG "${llvmPackages_14.llvm.dev}/bin/llvm-config" \
      --set-default CHPL_HOST_COMPILER llvm \
      --set-default CHPL_HOST_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_HOST_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_TARGET_CPU none \
      --set-default CHPL_TARGET_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_TARGET_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_GMP system \
      --set-default CHPL_RE2 bundled \
      --set-default CHPL_UNWIND system \
      --add-flags "-I ${llvmPackages_14.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include" \
      --add-flags "-L ${gmp}/lib" \
      --add-flags "-L ${xz.out}/lib"

    wrapProgram $out/util/printchplenv \
      --prefix PATH : "${python3}/bin" \
      --prefix PATH : "${pkg-config}/bin" \
      --prefix PATH : "${which}/bin" \
      --prefix PKG_CONFIG_PATH : "${libunwind.dev}/lib/pkgconfig" \
      --set-default CHPL_LLVM system \
      --set-default CHPL_LLVM_CONFIG "${llvmPackages_14.llvm.dev}/bin/llvm-config" \
      --set-default CHPL_HOST_COMPILER llvm \
      --set-default CHPL_HOST_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_HOST_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_TARGET_CPU none \
      --set-default CHPL_TARGET_CC "${llvmPackages_14.clang}/bin/clang" \
      --set-default CHPL_TARGET_CXX "${llvmPackages_14.clang}/bin/clang++" \
      --set-default CHPL_GMP system \
      --set-default CHPL_RE2 bundled \
      --set-default CHPL_UNWIND system

    ln -s $out/util/printchplenv $out/bin/
  '';

  buildInputs = [
    llvmPackages_14.clang
    llvmPackages_14.llvm
    llvmPackages_14.libclang.dev
    libunwind
    gmp
    # mpi
    pmix
    rdma-core
  ];

  nativeBuildInputs = [
    bash
    cmake
    gnumake
    gnum4
    file
    llvmPackages_14.clang
    makeWrapper
    perl
    pkg-config
    python3
    which
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
