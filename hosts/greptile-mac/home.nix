# Work MacBook home-manager modules
{...}: {
  imports = [
    # Base home config
    ../../modules/home/base.nix

    ../../modules/home/darwin.nix
    ../../modules/home/greptile.nix
    # Plugins for the Paseo cask (on Linux, applications.nix imports this)
    ../../modules/home/paseo.nix
  ];
}
