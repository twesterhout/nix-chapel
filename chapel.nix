{ bash
, cmake
, coreutils
, fetchFromGitHub
, file
, gcc-unwrapped
, gmp
, gnumake
, gnum4
, libunwind
, llvmPackages_14
, makeWrapper
, mpi
, perl
, pmix
, python39
, pkg-config
, rdma-core
, which
, xz
}:

llvmPackages_14.stdenv.mkDerivation rec {
  pname = "chapel";
  version = "1.31.0";

  src = fetchFromGitHub {
    owner = "chapel-lang";
    repo = "chapel";
    rev = "1ec5aa5cd391e2c94f67b49577e5f532001223a2";
    sha256 = "sha256-fPYEdLaI34L95vxPo321NLpItso1UaHYUyJvQyx+IBw=";
  };

  outputs = [ "out" "third_party" ];

  patches = [ ./llvm-and-clang-paths.patch ];
  postPatch = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall
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
    # make -j
    for CHPL_LIB_PIC in none pic; do
      make CHPL_LIB_PIC=$CHPL_LIB_PIC -j
    done
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=smp -j
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp -j
    make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp CHPL_LAUNCHER=none -j
    for CHPL_LAUNCHER in none gasnetrun_mpi slurm-gasnetrun_mpi slurm-srun; do
      make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=mpi CHPL_LAUNCHER=$CHPL_LAUNCHER -j
    done
    for CHPL_LAUNCHER in none gasnetrun_ibv slurm-gasnetrun_ibv; do
      make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=ibv CHPL_LAUNCHER=$CHPL_LAUNCHER -j
    done
  '';

  postInstall = ''
    mkdir -p $third_party
    cp -v -r $out/third-party/gasnet $third_party
    find $third_party -type d -name "include" -exec rm -r {} +
    find $third_party -type d -name "lib" -exec rm -r {} +
    find $third_party -type d -name "share" -exec rm -r {} +
    find $third_party -type f -name "Makefile*" -exec rm {} +

    makeWrapper $out/bin/linux64-x86_64/chpl $out/bin/chpl \
      --prefix PATH : "${pkg-config}/bin" \
      --prefix PATH : "${coreutils}/bin" \
      --prefix PATH : "${gnumake}/bin" \
      --prefix PATH : "${mpi}/bin" \
      --prefix PATH : "${python39}/bin" \
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
      --prefix PATH : "${python39}/bin" \
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
    mpi
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
    python39
    which
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
