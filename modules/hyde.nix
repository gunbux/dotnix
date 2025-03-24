{inputs, ...}: {
  nixpkgs.pkgs = import inputs.hydenix.inputs.hydenix-nixpkgs {
    inherit (inputs.hydenix.lib) system;
    config.allowUnfree = true;
    overlays = [
      inputs.hydenix.lib.overlays
    ];

    userPkgs = inputs.nixpkgs {
      config.allowUnfree = true;
    };
  };
}
