# Repository guidance

This repository manages NixOS systems, Home Manager configurations, custom packages, and application dotfiles.

## Structure

- `flake.nix` defines all supported system and Home Manager configurations.
- `base.nix` contains common NixOS configuration.
- `hosts/<host>/` contains hardware and host-specific settings.
- `modules/` contains reusable NixOS modules.
- `modules/home/` contains reusable Home Manager modules.
- `pkgs/<package>/default.nix` contains custom package definitions.
- `config/` contains application configuration linked through Home Manager.
- `secrets/secrets.yaml` contains SOPS-encrypted values.

Keep broadly reusable settings in modules and machine-specific settings under `hosts/`. Add new custom packages through the overlay in `flake.nix`.

## Supported configurations

The NixOS configurations are:

- `chun-lappy`
- `legion-nix`
- `fw12`
- `wsl`

The standalone Home Manager configuration is `non-nixos`.

When changing shared modules, account for every configuration that imports them.

## Validation

Format modified Nix files with:

```bash
alejandra <files>
```

Evaluate a changed NixOS configuration without activating it:

```bash
nix eval --no-write-lock-file \
  .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

Evaluate the standalone Home Manager configuration with:

```bash
nix eval --no-write-lock-file \
  .#homeConfigurations.non-nixos.activationPackage.drvPath
```

For changes affecting shared configuration, evaluate every affected host. Use `nix flake show --no-write-lock-file` as a lightweight check of the flake outputs.

Only build or activate a system when explicitly requested. The normal activation command is:

```bash
nh os switch . -H <host>
```

Report which configurations were evaluated and any configurations that could not be checked.

## Nix conventions

- Preserve the existing Alejandra formatting style.
- Prefer small modules with explicit imports over adding unrelated settings to `base.nix`.
- Preserve `system.stateVersion` and `home.stateVersion` unless a migration is specifically required.
- Keep flake inputs following `nixpkgs` where the upstream input supports it.
- Update `flake.lock` only when the dependency change is intentional.
- Preserve comments that explain hardware workarounds, pinned dependencies, or intentionally disabled services.
- Treat `hardware-configuration.nix` as generated machine state; edit it only for a deliberate hardware configuration change.

## Secrets

Keep secret values encrypted with SOPS. Never place plaintext credentials, tokens, passwords, or private keys in Nix modules, application configs, logs, or commits.

When an application needs a secret, expose it through `sops.secrets` or render it through `sops.templates`. Preserve restrictive ownership and file modes.

Do not decrypt `secrets/secrets.yaml` merely to inspect or validate unrelated changes.

## Working tree

The working tree may contain unrelated user changes. Inspect the diff before editing, preserve unrelated modifications, and keep formatting scoped to files involved in the task.
