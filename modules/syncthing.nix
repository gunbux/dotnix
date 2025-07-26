{...}: {
  services.syncthing = {
    enable = true;
    user = "chun";
    dataDir = "/home/chun/Documents";
    configDir = "/home/chun/.config/syncthing";
  };
}
