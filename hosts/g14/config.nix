{
  # Should be defined by base alrady
  username = "chun";
  gitUser = "Chun Yu";
  gitEmail = "lamchunyu00@gmail.com";
  host = "chun-lappy";
  defaultPassword = "NixOS!";
  timezone = "Asia/Singapore";
  locale = "en_US.UTF-8";

  hardwareConfig = toString ./hardware-configuration.nix;

  nixModules = [
    ./default.nix
  ];

  # List of nix modules to import in ./lib/mkConfig.nix
  homeModules = [
    ../../home.nix

    # HyDE-specific modules
    ../../modules/home/swaylock.nix
    ../../modules/home/hyprland.nix
    ../../modules/home/dunst.nix
  ];

  hyde = rec {
    sddmTheme = "Corners"; # or "Corners"

    enable = true;

    # active theme, must be in themes list
    activeTheme = "Catppuccin Mocha";

    # list of themes to choose from
    themes = [
      # -- Default themes
      # "Catppuccin Latte"
      "Catppuccin Mocha"
      # "Decay Green"
      # "Edge Runner"
      # "Frosted Glass"
      # "Graphite Mono"
      # "Gruvbox Retro"
      # "Material Sakura"
      # "Nordic Blue"
      # "Rose Pine"
      # "Synth Wave"
      "Tokyo Night"

      # -- Themes from hyde-gallery
      # "Abyssal-Wave"
      # "AbyssGreen"
      # "Bad Blood"
      # "Cat Latte"
      # "Crimson Blade"
      # "Dracula"
      # "Edge Runner"
      "Green Lush"
      # "Greenify"
      # "Hack the Box"
      # "Ice Age"
      # "Mac OS"
      # "Monokai"
      # "Monterey Frost"
      # "One Dark"
      # "Oxo Carbon"
      # "Paranoid Sweet"
      # "Pixel Dream"
      # "Rain Dark"
      # "Red Stone"
      # "Rose Pine"
      # "Scarlet Night"
      # "Sci-fi"
      # "Solarized Dark"
      # "Vanta Black"
      # "Windows 11"
    ];

    # Exactly the same as hyde.conf
    conf = {
      hydeTheme = activeTheme;
      wallFramerate = 120;
      wallTransDuration = 0.4;
      wallAddCustomPath = "";
      enableWallDcol = 2;
      wallbashCustomCurve = "";
      skip_wallbash = [];
      themeSelect = 2;
      rofiStyle = 2;
      rofiScale = 7;
      wlogoutStyle = 1;
    };
  };

  vm = {
    # 4 GB minimum
    memorySize = 4096;
    # 2 cores minimum
    cores = 2;
    # 30GB minimum for one theme - 50GB for multiple themes - more for development and testing
    diskSize = 20000;
  };
}
