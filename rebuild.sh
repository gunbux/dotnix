#!/bin/sh

# Rebuild system
# sudo nixos-rebuild -I nixos-config=./base.nix switch
# sudo nixos-rebuild -I nixos-config=./base.nix switch --show-trace --keep-failed
sudo nixos-rebuild -I nixos-config=./base.nix switch --show-trace
