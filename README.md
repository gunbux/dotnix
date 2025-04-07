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
sudo nixos-rebuild switch --flake .#chun-lappy

# With nh
nh os switch . (-H chun-lappy)
```

## Adding mutt configs

There's no good way to configure mutt/neomutt using Nix configurations, so we can just symlink/copy the folder over.

```
ln -sf /home/chun/dotnix/config/mutt ~/.config/mutt
```

## Running wireguard

If you're running wireguard on boot (wifi), wg0 will fail to autostart, so autostart is disabled. To start the vpn, run:

```nix
sudo systemctl start wg-quick-wg0
```
