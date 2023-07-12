{ writeShellScriptBin
, chapel
}:

writeShellScriptBin "chapelFixupBinary" ''
  set -e

  replaceReferencesWith() {
    sed -i "s:$2:$3:g" "$1"
  }

  hideReferencesTo() {
    declare -r filepath=$1
    declare -r original=$2
    declare -r new=$(echo "$original" | sed -E 's:/nix/store/[a-z0-9]{32}-:/nix/store/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX-:')
    replaceReferencesWith "$filepath" "$original" "$new"
  }

  if [ $# -ne 1 ]; then
    echo "Expected a single argument -- binary to fixup"
    exit 1
  fi

  binaryFile=$1
  hideReferencesTo "$binaryFile" ${chapel.llvmPackages.clang}
  hideReferencesTo "$binaryFile" ${chapel.llvmPackages.clang-unwrapped.lib}
  hideReferencesTo "$binaryFile" ${chapel.llvmPackages.llvm.dev}
  hideReferencesTo "$binaryFile" ${chapel.llvmPackages.bintools.libc.dev}
  if ! strings $binaryFile | grep -q -E 'CHPL_LAUNCHER:\s+none'; then
    echo 'Replacing references to $CHPL_HOME/third-party ...'
    replaceReferencesWith "$binaryFile" ${chapel}/third-party/ ${chapel.third_party}/
  fi
  hideReferencesTo "$binaryFile" ${chapel}
''
