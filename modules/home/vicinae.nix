{
  config,
  pkgs,
  ...
}: let
  # Store extensions are built from the vicinaehq/extensions monorepo; bump
  # rev/hash together to update them.
  extensionNames = [
    "bitwarden"
    "bluetooth"
    "color-converter"
    "github"
    "it-tools"
    "niri"
    "niri-monitors"
    "nix"
    "process-manager"
    "pulseaudio"
    "systemd"
    "wifi-commander"
  ];

  extensionsSrc = pkgs.fetchFromGitHub {
    owner = "vicinaehq";
    repo = "extensions";
    rev = "0e3953058fb787d2a96e5ac0cec462440c07cd07";
    sparseCheckout = map (name: "extensions/${name}") extensionNames;
    hash = "sha256-JUWHgrgy2IfeNXYbML4nVkxH2O9aJgCt8uT0YW2Y828=";
  };

  # dbus-next pulls in the optional native usocket module, which fails to
  # build under node-gyp in the sandbox and has unlocked deps; dbus-next falls
  # back to plain sockets without it.
  dropUsocket = ["bluetooth" "systemd"];

  mkStoreExtension = name:
    (config.lib.vicinae.mkExtension {
      inherit name;
      src = "${extensionsSrc}/extensions/${name}";
    }).overrideAttrs (pkgs.lib.optionalAttrs (builtins.elem name dropUsocket) {
      npmRebuildFlags = ["--ignore-scripts"];
      preBuild = "rm -rf node_modules/usocket";
    });
in {
  # App launcher on Mod+Space (niri binds); the daemon keeps the window warm.
  programs.vicinae = {
    enable = true;
    systemd.enable = true;

    extensions = map mkStoreExtension extensionNames;

    settings = {
      # Bundled theme; matches Noctalia's builtin Catppuccin.
      theme = {
        dark.name = "catppuccin-mocha";
        light.name = "catppuccin-latte";
      };
    };
  };

  # Backend for the bitwarden extension.
  programs.rbw = {
    enable = true;
    settings = {
      email = "lamchunyu00@gmail.com";
      # Vicinae runs outside a terminal, so unlock needs a graphical prompt.
      pinentry = pkgs.pinentry-qt;
    };
  };
}
