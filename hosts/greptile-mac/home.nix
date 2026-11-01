# Work MacBook home-manager modules
{...}: {
  imports = [
    # Base home config
    ../../modules/home/base.nix

    ../../modules/home/paseo.nix
    ../../modules/home/darwin.nix
    ../../modules/home/greptile.nix
  ];
}
