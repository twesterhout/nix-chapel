#! @shell@ -e

if [ $# -ne 1 ]; then
  echo "Expected a single argument -- binary to fixup"
  exit 1
fi

binaryFile=$1

export PATH=@removeReferencesTo@/bin:$PATH
remove-references-to -t @llvmPackages.clang@ "$binaryFile"
remove-references-to -t @llvmPackages.clang-unwrapped.lib@ "$binaryFile"
remove-references-to -t @llvmPackages.llvm.dev@ "$binaryFile"
remove-references-to -t @llvmPackages.bintools.libc.dev@ "$binaryFile"
remove-references-to -t @chplStdenv.cc.libc.dev@ "$binaryFile"
sed -i "s:@out@/third-party/:@third_party@/:g" "$binaryFile"
remove-references-to -t @out@ "$binaryFile"
