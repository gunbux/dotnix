<p align="center">
  <img src="assets/icon.png" alt="dotnix icon" width="160">
</p>

# Chun's dotfiles

## Building the system

```bash
nh os switch . (-H chun-lappy)
```

## Installing the Eevee cursor

The niri hosts use the paid Eevee Chunky Cursor, which is not in this repo. Without it, the cursor falls back to Banana.

1. Unzip `Eevee_linux.zip` from the "Eevee Chunky Cursor.zip" purchase.
2. Copy its `scm-eevee-c16f477d` folder to `~/.local/share/icons/`.
3. Run `nh os switch . -H <host>`. Activation picks the cursor, so switch again after adding or removing the folder.

## Running wireguard

If you're running wireguard on boot (wifi), wg0 will fail to autostart, so autostart is disabled. To start the vpn, run:

```nix
sudo systemctl start wg-quick-wg0
```
