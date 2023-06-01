# Chapel + Nix = ❤️

This repository provides a [Nix](https://nixos.org/) flake for [Chapel](https://chapel-lang.org/).

Think about this project as a *composable* alternative to the [official Docker images](https://hub.docker.com/u/chapel). Composability here means that it's trivial to add external library dependencies, introduce other languages to the mix, etc. all while retaining the ability to benefit from binary caching (i.e. you don't have to build everything from source).





## Internal TODOs

- [ ] Upstream patches for locating system LLVM and Clang
- [ ] How to disable date stamps in GASNet builds?


