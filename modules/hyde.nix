{inputs, ...}: {
  nixpkgs.pkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
    overlays = [
      inputs.hydenix.overlays.default
    ];

    userPkgs = inputs.nixpkgs {
      config.allowUnfree = true;
    };
  };
}
