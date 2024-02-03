{ bash
, cmake
, coreutils
, fetchFromGitHub
, file
, gcc
, gmp
, gnumake
, gnum4
, lib
, libunwind
, llvmPackages
, makeWrapper
, patchelf
, perl
, pmix
, python3
, python3Packages
, pkg-config
, rdma-core
, stdenv
, which
, xz
, compiler ? "llvm"
, settings ? { }
}:

assert compiler == "llvm" || compiler == "gnu";

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

  commonSettings = {
    CHPL_GMP = "system";
    CHPL_RE2 = "bundled";
    CHPL_UNWIND = if llvmPackages.stdenv.isDarwin then "none" else "system";
    CHPL_LAUNCHER = "none";
    CHPL_TARGET_MEM = "jemalloc";
    CHPL_TARGET_CPU = "none";
  } // lib.optionalAttrs llvmPackages.stdenv.isLinux {
    PMI_HOME = "${pmix}";
  };

  llvmSpecificSettings = {
    CC = "${llvmPackages.clang}/bin/cc";
    CXX = "${llvmPackages.clang}/bin/c++";
    CHPL_LLVM = "system";
    CHPL_LLVM_CONFIG = "${llvmPackages.llvm.dev}/bin/llvm-config";
    CHPL_HOST_COMPILER = "llvm";
    CHPL_HOST_CC = "${llvmPackages.clang}/bin/clang";
    CHPL_HOST_CXX = "${llvmPackages.clang}/bin/clang++";
    CHPL_TARGET_CC = "${llvmPackages.clang}/bin/clang";
    CHPL_TARGET_CXX = "${llvmPackages.clang}/bin/clang++";
  };

  gnuSpecificSettings = {
    CC = "${gcc}/bin/cc";
    CXX = "${gcc}/bin/c++";
    CHPL_LLVM = "none";
    CHPL_HOST_COMPILER = "gnu";
    CHPL_HOST_CC = "${gcc}/bin/gcc";
    CHPL_HOST_CXX = "${gcc}/bin/g++";
    CHPL_TARGET_CC = "${gcc}/bin/gcc";
    CHPL_TARGET_CXX = "${gcc}/bin/g++";
  };

  chplSettings = commonSettings // (if compiler == "llvm" then llvmSpecificSettings else gnuSpecificSettings) // settings;
  chplStdenv = if compiler == "llvm" then llvmPackages.stdenv else stdenv;

  chplBuildEnv = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}='${v}'") chplSettings);

  wrapperArgs = lib.concatStringsSep " " ([
    "--prefix PATH : '${lib.makeBinPath [coreutils gnumake pkg-config python3 which]}'"
    "--set-default CHPL_HOME $out"
  ]
  ++ (lib.mapAttrsToList (k: v: "--set-default ${k} '${v}'") chplSettings)
  ++ lib.optionals (!chplStdenv.isDarwin) [
    "--prefix PKG_CONFIG_PATH : '${libunwind.dev}/lib/pkgconfig'"
  ]);

  compilerSpecificWrapperArgs = lib.concatStringsSep " " ([
    "--add-flags '-L ${xz.out}/lib'"
  ]
  ++ lib.optionals (chplSettings.CHPL_GMP == "system") [
    "--add-flags '-L ${gmp}/lib'"
  ]
  ++ lib.optionals (!chplStdenv.isDarwin && compiler == "llvm") [
    "--add-flags '-I ${llvmPackages.clang-unwrapped.lib}/lib/clang/${llvmPackages.clang.version}/include'"
    "--add-flags '-I ${llvmPackages.clang}/resource-root/include'"
    "--add-flags '-I ${llvmPackages.bintools.libc.dev}/include'"
  ]
  ++ lib.optionals (!chplStdenv.isDarwin && compiler == "gnu") [
    "--add-flags '-I ${chplStdenv.cc.libc.dev}/include'"
  ]);
in
chplStdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.34.0-pre";
  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "477aacb9bf0027d7977a4a5e788ff92597ef3482"; # 30 Jan 2024
    hash = "sha256-EUjhxiLiXdqdgpB9dYT7YVwALJO1ElAYfgKutkfLdXc=";
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

    export CHPL_DONT_BUILD_CHPLDOC_VENV=1
    export CHPL_DONT_BUILD_TEST_VENV=1
    export CHPL_DONT_BUILD_C2CHAPEL_VENV=1

    # Needed until https://github.com/chapel-lang/chapel/issues/24128 is resolved
    substituteInPlace third-party/Makefile \
      --replace 'cd chpl-venv && $(MAKE) c2chapel-venv' \
                'if [ -z "$$CHPL_DONT_BUILD_C2CHAPEL_VENV" ]; then cd chpl-venv && $(MAKE) c2chapel-venv; fi'
    # tools/c2chapel/Makefile \
    #   --replace 'c2chapel-venv $(FAKES)' '$(FAKES)'

    # This is essentially what the $(FAKES) target in the Makefile does, but
    # we use $${c2chapel-fake-headers} instead of downloading the archive from
    # the internet
    pushd tools/c2chapel
    mkdir -p install/fakeHeaders
    cp --no-preserve=mode -r ${c2chapel-fake-headers}/utils/fake_libc_include/* install/fakeHeaders/
    ./utils/fixFakes.sh install/fakeHeaders utils/custom.h
    mkdir -p install/fakeHeaders/utils
    cp utils/custom.h install/fakeHeaders/utils/
    popd
  '';

  configurePhase = ''
    export ${chplBuildEnv}
    ./configure --chpl-home=$out
  '';
  # ''
  #   export CC=${llvmPackages.clang}/bin/cc
  #   export CXX=${llvmPackages.clang}/bin/c++
  #   export CHPL_LLVM=system
  #   export CHPL_LLVM_CONFIG=${llvmPackages.llvm.dev}/bin/llvm-config
  #   export CHPL_HOST_COMPILER=llvm
  #   export CHPL_HOST_CC=${llvmPackages.clang}/bin/clang
  #   export CHPL_HOST_CXX=${llvmPackages.clang}/bin/clang++
  #   export CHPL_TARGET_CC=${llvmPackages.clang}/bin/clang
  #   export CHPL_TARGET_CXX=${llvmPackages.clang}/bin/clang++
  #   export CHPL_GMP=system
  #   export CHPL_RE2=bundled
  #   export CHPL_UNWIND=${if llvmPackages.stdenv.isDarwin then "none" else "system"}
  # '' + lib.optionalString llvmPackages.stdenv.isLinux ''
  #   export PMI_HOME=${pmix}
  # '' + ''
  #   export CHPL_LAUNCHER=none
  #   export CHPL_TARGET_MEM=jemalloc
  #   export CHPL_TARGET_CPU=none

  #   ./configure --chpl-home=$out
  # '';

  buildPhase = ''
    make -j$NIX_BUILD_CORES
    make -j$NIX_BUILD_CORES c2chapel
  '';
  #   CHPL_LIB_PIC=none
  #   make -j$NIX_BUILD_CORES CHPL_LIB_PIC=pic
  # '' + lib.optionalString (compiler == "gnu") ''
  #   for chpl_lib_pic in none pic; do
  #     make -j$NIX_BUILD_CORES \
  #       CHPL_LIB_PIC=$chpl_lib_pic \
  #       CHPL_TARGET_MEM=cstdlib CHPL_HOST_MEM=cstdlib \
  #       CHPL_UNWIND=none \
  #       CHPL_TASKS=fifo \
  #       CHPL_SANITIZE_EXE=address

  #     make -j$NIX_BUILD_CORES \
  #       CHPL_LIB_PIC=pic CHPL_UNWIND=none \
  #       CHPL_TARGET_MEM=cstdlib CHPL_HOST_MEM=cstdlib \
  #       CHPL_TASKS=qthreads

  #   done
  # '';

  enableParallelBuilding = true;

  # buildPhase = ''
  #   for arch in none nehalem; do
  #     export CHPL_TARGET_CPU=$arch

  #     # C backend
  #     make CHPL_TARGET_COMPILER=gnu CHPL_TARGET_CC=gcc CHPL_TARGET_CXX=g++ CHPL_LIB_PIC=pic -j$NIX_BUILD_CORES

  #     # Single locale
  #     make CHPL_COMM=none CHPL_LIB_PIC=none -j$NIX_BUILD_CORES
  #     make CHPL_COMM=none CHPL_LIB_PIC=pic -j$NIX_BUILD_CORES
  #     # SMP
  #     make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=smp -j$NIX_BUILD_CORES
  # '' + lib.optionalString llvmPackages.stdenv.isLinux ''
  #   # Infiniband
  #   # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=everything CHPL_TARGET_MEM=cstdlib -j$NIX_BUILD_CORES
  #   make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=fast -j$NIX_BUILD_CORES
  #   # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_GASNET_SEGMENT=large -j$NIX_BUILD_CORES
  #   # UDP
  #   make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp CHPL_LAUNCHER=none -j$NIX_BUILD_CORES
  # '' + ''
  #     make c2chapel -j$NIX_BUILD_CORES
  #   done
  # '';

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
      ${wrapperArgs} \
      ${compilerSpecificWrapperArgs}

    wrapProgram $out/util/printchplenv \
      ${wrapperArgs}

    ln -s $out/util/printchplenv $out/bin/

  '' + lib.optionalString llvmPackages.stdenv.isLinux ''
    # libChplFrontendShared.so contains a reference to lib/compiler/linux64-x86_64 in its RPATH.
    # This folder contains libChplFrontend.so, but libChplFrontend.so has also
    # been installed to $out/lib/compiler/linux64-x86_64. Remove the temporary
    # build folder and instead add $ORIGIN to RPATH
    rm -r lib/compiler/linux64-x86_64
    patchelf --add-rpath '$ORIGIN' $out/lib/compiler/linux64-x86_64/libChplFrontendShared.so
  '';

  buildInputs =
    lib.optionals (chplSettings.CHPL_UNWIND == "system") [ libunwind ]
    ++ lib.optionals (chplSettings.CHPL_GMP == "system") [ gmp ]
    ++ lib.optionals (compiler == "llvm") [ llvmPackages.clang llvmPackages.llvm llvmPackages.libclang.dev ]
    ++ lib.optionals chplStdenv.isLinux [ pmix rdma-core ];

  nativeBuildInputs = [
    bash
    cmake
    gnumake
    gnum4
    file
    makeWrapper
    patchelf
    perl
    pkg-config
    python3
    which
  ] ++ lib.optionals (compiler == "llvm") [
    llvmPackages.clang
  ] ++ lib.optionals (compiler == "gnu") [
    gcc
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
