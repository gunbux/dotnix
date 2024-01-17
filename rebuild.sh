#!/bin/sh
sudo nixos-rebuild -I nixos-config=./base.nix switch --show-trace --upgrade
