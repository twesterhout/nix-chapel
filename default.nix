{
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/5ed481943351e9fd354aeb557679624224de38d5.tar.gz") { }
}:
  {
    chapel = pkgs.callPackage ./chapel.nix { };
  }
