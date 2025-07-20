# Chun's dotfiles

## Building the system

```bash
nh os switch . (-H chun-lappy)
```

## Running wireguard

If you're running wireguard on boot (wifi), wg0 will fail to autostart, so autostart is disabled. To start the vpn, run:

```nix
sudo systemctl start wg-quick-wg0
```
