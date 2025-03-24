{pkgs, ...}: {
  # Additional hyde speific config
  programs.zsh = {
    initExtraFirst = ''
      #Display Pokemonks
      pokego --no-title -r 1-6
    '';
  };

  # hydenix home-manager options go here
  hydenix.hm = {
    #! Important options
    enable = true;

    # NOT MANAGED BY HYDENIX
    editors.enable = false;
    git.enable = false;
    shell = {
      enable = true; # enable shell module
      zsh.enable = false; # enable zsh shell
      zsh.configText = ""; # zsh config text
      bash.enable = false; # enable bash shell
      fish.enable = false; # enable fish shell
      pokego.enable = true; # enable Pokemon ASCII art scripts
    };

    comma.enable = true;
    dolphin.enable = true;
    fastfetch.enable = true; # fastfetch configuration
    firefox = {
      enable = true; # enable firefox module
      useHydeConfig = false; # use hyde firefox configuration and extensions
      useUserChrome = true; # if useHydeConfig is true, apply hyde userChrome CSS customizations
      useUserJs = true; # if useHydeConfig is true, apply hyde user.js preferences
      useExtensions = true; # if useHydeConfig is true, install hyde firefox extensions
    };
    gaming.enable = true; # enable gaming module
    hyde.enable = true; # enable hyde module
    hyprland.enable = true; # enable hyprland module
    lockscreen = {
      enable = true; # enable lockscreen module
      hyprlock = false; # enable hyprlock lockscreen
      swaylock = true; # enable swaylock lockscreen
    };
    notifications.enable = false;
    qt.enable = true; # enable qt module
    gtk.enable = true;
    rofi.enable = true; # enable rofi module
    screenshots = {
      enable = true; # enable screenshots module
      grim.enable = true; # enable grim screenshot tool
      slurp.enable = true; # enable slurp region selection tool
      satty.enable = true; # enable satty screenshot annotation tool
      swappy.enable = false; # enable swappy screenshot editor
    };
    social = {
      enable = true; # enable social module
      discord = true; # enable discord module
      webcord = true; # enable webcord module
      vesktop = true; # enable vesktop module
    };
    spotify.enable = true; # enable spotify module
    swww.enable = true; # enable swww wallpaper daemon
    terminals = {
      enable = false; # enable terminals module
      kitty.enable = true; # enable kitty terminal
      kitty.configText = ""; # kitty config text
    };
    theme = {
      enable = true; # enable theme module
      active = "Catppuccin Mocha"; # active theme name
      themes = [
        "Catppuccin Mocha"
        "Catppuccin Latte"
      ]; # default enabled themes, full list in https://github.com/richen604/hydenix/tree/main/hydenix/sources/themes
    };
    waybar.enable = true; # enable waybar module
    wlogout.enable = true; # enable wlogout module
    xdg.enable = true; # enable xdg module
  };
}
