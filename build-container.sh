#!/bin/bash

main() {
	declare -r unpack=$(mktemp -d)
	tar xzf ./result -C "$unpack"
	tar -C "$unpack/" -cf layer.tar .
	singularity build container.sif Singularity.nightly
	rm -r "$unpack"
}

main
