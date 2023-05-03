#!/bin/bash

set -e

main() {
    declare -r unpack=$(mktemp -d)
    tar xzf "$1" -C "$unpack"
    tar -C "$unpack/" -cf layer.tar .
    singularity build --fakeroot container.sif Singularity.nightly
    chown -R $(whoami):$(whoami) "$unpack"
    chmod -R 777 "$unpack"
    rm -rf "$unpack"
    rm -f layer.tar
}

main "$@"
