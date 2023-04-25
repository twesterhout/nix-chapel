{ llvmPackages_14
, gmp
, coreutils
, xz
, libunwind
, fetchFromGitHub
, python39
, bash
, gnumake
, gnum4
, which
, cmake
, mpi
, rdma-core
, pkg-config
, makeWrapper
, perl
}:

llvmPackages_14.stdenv.mkDerivation {
  pname = "chapel";
  version = "1.30.0";

  src = fetchFromGitHub {
    owner = "bradcray";
    repo = "chapel";
    rev = "build-amudprun-host-with-host-cc";
    sha256 = "sha256-6Ijg8vfeozxCrEp9ZyWg9lf5bdB8+DDNBQTQU126VJ8=";
  };
  # src = fetchFromGitHub {
  #   owner = "chapel-lang";
  #   repo = "chapel";
  #   rev = "a5d4cf00ac813be8e77203bcdd76aea7bddff940";
  #   sha256 = "sha256-uh2HFx8R8/fIWwaKOnkpLza+Q+AaXoBNnVPaVblZ7oM=";
  # };

  patches = [ ./llvm-and-clang-paths.patch ];
  postPatch = ''
    # substituteInPlace third-party/gasnet/gasnet-src/other/amudp/Makefile.common \
    #   --replace 'CC = gcc' 'CC = cc' \
    #   --replace 'CXX = g++' 'CXX = c++'
  '';

  configurePhase = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall

    export CC=${llvmPackages_14.stdenv.cc}/bin/cc
    export CXX=${llvmPackages_14.stdenv.cc}/bin/c++
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

    ./configure --chpl-home=$out
  '';

  buildPhase = ''
    make -j
    for CHPL_COMM_SUBSTRATE in smp mpi udp ibv; do
      make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=$CHPL_COMM_SUBSTRATE -j
    done
    # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=udp -j
    # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=mpi -j
    # make CHPL_COMM=gasnet CHPL_COMM_SUBSTRATE=smp -j
    # for CHPL_LIB_PIC in none pic; do
    #   for CHPL_UNWIND in none system; do
    #     make  CHPL_UNWIND=$CHPL_UNWIND CHPL_LIB_PIC=$CHPL_LIB_PIC -j
    #   done
    # done
  '';

  postInstall = ''
    makeWrapper $out/bin/linux64-x86_64/chpl $out/bin/chpl \
      --prefix PATH : "${llvmPackages_14.clang}/bin" \
      --prefix PATH : "${pkg-config}/bin" \
      --prefix PATH : "${mpi}/bin" \
      --prefix PATH : "${coreutils}/bin" \
      --prefix PATH : "${gnumake}/bin" \
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
  '';

  checkPhase = ''
    export PATH=$PWD/bin/linux64-x86_64:$PATH
    wrapProgram bin/linux64-x86_64/chpl \
      --add-flags "-I ${llvmPackages_14.bintools.libc.dev}/include" \
      --add-flags "-I ${llvmPackages_14.clang-unwrapped.lib}/lib/clang/14.0.6/include" \
      --add-flags "-L ${gmp}/lib" \
      --add-flags "-L ${xz.out}/lib"
    mv bin/linux64-x86_64/.chpl-wrapped bin/linux64-x86_64/chpl
  '';

  doCheck = false;

  buildInputs = [
    llvmPackages_14.clang
    llvmPackages_14.llvm
    llvmPackages_14.libclang.dev
    libunwind
    gmp
    mpi
    rdma-core
  ];

  nativeBuildInputs = [
    bash
    python39
    gnumake
    gnum4
    which
    cmake
    perl
    pkg-config
    llvmPackages_14.clang
    makeWrapper
  ];

  meta = {
    description = "a Productive Parallel Programming Language";
    homepage = "https://chapel-lang.org/";
  };
}
