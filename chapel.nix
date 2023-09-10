{ bash
, cmake
, coreutils
, fetchFromGitHub
, file
, gmp
, gnumake
, gnum4
, lib
, libunwind
, llvmPackages
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
      hash = "sha256-M2Col80YezCyRpKSKBPav8HrLhfmbzLxAIpVz0ULBYg=";
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
      hash = "sha256-PYfYOukddeo7SN6B9GYNY2mj3S1Dhk0ONw8ycOoYPWA=";
    };
    propagatedBuildInputs = with python3Packages; [
      pycparser
      ply
    ];
  };
in
llvmPackages.stdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.32.0-pre";
  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "e3a9c913516ac9abf48c9a8b86c199953f12030f"; # 15 Aug 2023
    hash = "sha256-MzCIzJdFAjK/BNx6C6gaF/3Y9lmw08CauVJfu6N+YrE=";
  };

  outputs = [ "out" "third_party" ];

  c2chapel-fake-headers = fetchFromGitHub {
    owner = "eliben";
    repo = "pycparser";
    rev = "0055facfb5b5289ce8ef2ef12b18e34a223f9d20";
    hash = "sha256-M2Col80YezCyRpKSKBPav8HrLhfmbzLxAIpVz0ULBYg=";
  };

  passthru.llvmPackages = llvmPackages;

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
    export CC=${llvmPackages.clang}/bin/cc
    export CXX=${llvmPackages.clang}/bin/c++
    export CHPL_LLVM=system
    export CHPL_LLVM_CONFIG=${llvmPackages.llvm.dev}/bin/llvm-config
    export CHPL_HOST_COMPILER=llvm
    export CHPL_HOST_CC=${llvmPackages.clang}/bin/clang
    export CHPL_HOST_CXX=${llvmPackages.clang}/bin/clang++
    export CHPL_TARGET_CC=${llvmPackages.clang}/bin/clang
    export CHPL_TARGET_CXX=${llvmPackages.clang}/bin/clang++
    export CHPL_GMP=system
    export CHPL_RE2=bundled
    export CHPL_UNWIND=system
  '' + lib.optionalString llvmPackages.stdenv.isLinux ''
    export PMI_HOME=${pmix}
  '' + ''
    export CHPL_LAUNCHER=none
    export CHPL_TARGET_MEM=jemalloc
    export CHPL_TARGET_CPU=none

    ./configure --chpl-home=$out
  '';

  buildPhase = ''
    for arch in none nehalem; do
      export CHPL_TARGET_CPU=$arch

      # Single locale
      make CHPL_COMM=none CHPL_LIB_PIC=none -j
      make CHPL_COMM=none CHPL_LIB_PIC=pic -j
      # SMP
      make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=smp -j
  '' + lib.optionalString llvmPackages.stdenv.isLinux ''
    # Infiniband
    # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=everything CHPL_TARGET_MEM=cstdlib -j
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=fast -j
    # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=large -j
    # UDP
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp CHPL_LAUNCHER=none -j
  '' + ''
      make -j c2chapel
    done
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
      --prefix PATH : "${python3}/bin" \
      --prefix PKG_CONFIG_PATH : "${libunwind.dev}/lib/pkgconfig" \
      --set-default CHPL_HOME $out \
      --set-default CHPL_LLVM system \
      --set-default CHPL_LLVM_CONFIG "${llvmPackages.llvm.dev}/bin/llvm-config" \
      --set-default CHPL_HOST_COMPILER llvm \
      --set-default CHPL_HOST_CC "${llvmPackages.clang}/bin/clang" \
      --set-default CHPL_HOST_CXX "${llvmPackages.clang}/bin/clang++" \
      --set-default CHPL_LAUNCHER none \
      --set-default CHPL_TARGET_CPU none \
      --set-default CHPL_TARGET_MEM jemalloc \
      --set-default CHPL_TARGET_CC "${llvmPackages.clang}/bin/clang" \
      --set-default CHPL_TARGET_CXX "${llvmPackages.clang}/bin/clang++" \
      --set-default CHPL_GMP system \
      --set-default CHPL_RE2 bundled \
      --set-default CHPL_UNWIND system \
      --add-flags "-I ${llvmPackages.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages.clang-unwrapped.lib}/lib/clang/${llvmPackages.clang.version}/include" \
      --add-flags "-L ${gmp}/lib" \
      --add-flags "-L ${xz.out}/lib"

    wrapProgram $out/util/printchplenv \
      --prefix PATH : "${python3}/bin" \
      --prefix PATH : "${pkg-config}/bin" \
      --prefix PATH : "${which}/bin" \
      --prefix PKG_CONFIG_PATH : "${libunwind.dev}/lib/pkgconfig" \
      --set-default CHPL_LLVM system \
      --set-default CHPL_LLVM_CONFIG "${llvmPackages.llvm.dev}/bin/llvm-config" \
      --set-default CHPL_HOST_COMPILER llvm \
      --set-default CHPL_HOST_CC "${llvmPackages.clang}/bin/clang" \
      --set-default CHPL_HOST_CXX "${llvmPackages.clang}/bin/clang++" \
      --set-default CHPL_LAUNCHER none \
      --set-default CHPL_TARGET_CPU none \
      --set-default CHPL_TARGET_MEM jemalloc \
      --set-default CHPL_TARGET_CC "${llvmPackages.clang}/bin/clang" \
      --set-default CHPL_TARGET_CXX "${llvmPackages.clang}/bin/clang++" \
      --set-default CHPL_GMP system \
      --set-default CHPL_RE2 bundled \
      --set-default CHPL_UNWIND system

    ln -s $out/util/printchplenv $out/bin/
  '';

  buildInputs = [
    llvmPackages.clang
    llvmPackages.llvm
    llvmPackages.libclang.dev
    libunwind
    gmp
  ] ++ lib.optionals llvmPackages.stdenv.isLinux [
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
    llvmPackages.clang
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
