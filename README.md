## Initial Setup

Ensure you are on the unstable channel:

```bash
nix-channel --add https://nixos.org/channels/nixos-unstable nixos
```

Also add sane hardware defaults with nixos-hardware

```bash
sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
sudo nix-channel --update
```

## Building the system

```bash
# Without flakes
nixos-rebuild -I nixos-config=./base.nix switch

# With flakes
sudo nixos-rebuild switch --flake .#chun-lappy --impure
```

## Adding mutt configs

There's no good way to configure mutt/neomutt using Nix configurations, so we can just symlink/copy the folder over.

```
ln -sf /home/chun/dotnix/config/mutt ~/.config/mutt
```
