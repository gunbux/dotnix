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

  # Enable hydenix
  hydenix = {
    enable = true;
    timezone = "Asia/Singapore";
    locale = "en_US.UTF-8";
    sddm.enable = false;
    boot = {
      enable = false; # enable boot module
    };
  };
}
