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
    rev = "413154812ffce610218c523b9c479febe46c5327";
    sparseCheckout = map (name: "extensions/${name}") extensionNames;
    hash = "sha256-XkUbqUmPEt3DlIBxwAylZcO1tf4cZDSDJl9LT4yC0tA=";
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

  # Runs the bridge on Paseo's bundled runtime so it reuses the installed CLI's
  # daemon client; see config/vicinae/paseo/bridge/paseo-bridge.mjs.
  paseoResources = pkgs.paseo-desktop.resources;
  paseoBridge = pkgs.writeShellScript "paseo-vicinae-bridge" ''
    exec env PASEO_RESOURCES=${paseoResources} ELECTRON_RUN_AS_NODE=1 PASEO_NODE_ENV=production \
      ${pkgs.paseo-desktop}/bin/paseo-desktop --disable-warning=DEP0040 \
      ${paseoResources}/app.asar.unpacked/dist/daemon/node-entrypoint-runner.js \
      node-script ${../../config/vicinae/paseo/bridge/paseo-bridge.mjs} "$@"
  '';

  paseoExtension =
    (config.lib.vicinae.mkExtension {
      name = "paseo";
      src = pkgs.lib.cleanSourceWith {
        src = ../../config/vicinae/paseo;
        filter = path: _: !(builtins.elem (baseNameOf path) ["node_modules" "bridge" "vicinae-env.d.ts"]);
      };
    }).overrideAttrs {
      postPatch = ''
        substituteInPlace src/lib/paseo.ts \
          --replace-fail "@paseoBridge@" "${paseoBridge}" \
          --replace-fail "@paseo@" "${pkgs.paseo-desktop}/bin/paseo"
      '';
    };
in {
  # App launcher on Mod+Space (niri binds); the daemon keeps the window warm.
  programs.vicinae = {
    enable = true;
    systemd.enable = true;

    extensions = map mkStoreExtension extensionNames ++ [paseoExtension];

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
