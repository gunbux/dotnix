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
nixos-rebuild -I nixos-config=./base.nix switch
```
