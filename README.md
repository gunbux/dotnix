# Personal NixOS Build

## Current Machines

- Asus G14 (2022) - `g14`
- Raspi - WIP `pi`

## Building the system

```bash
nixos-rebuild -I nixos-config=./base.nix switch
```
or just use the `rebuild.sh` script

## Performance Tuning

### `g14`

- `amd-pstate-epp` enabled (since 6.4)
- kernel patched with clear-linux packages
- gcc tuned with `march=native` and `mtune=native`
