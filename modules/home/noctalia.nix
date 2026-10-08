{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  # agent-glow 0.1.0 never matches Claude sessions (it searches the cached
  # family name instead of the cmdline) and misses Paseo's --resume=<uuid> and
  # Codex app-server sessions. world_clock gains a bar-only local clock that
  # follows tzupdate and hides when it matches a listed zone. Both override the
  # pinned copies via a later source.
  patchedPlugins = pkgs.runCommand "noctalia-patched-plugins" {} ''
    mkdir -p $out
    cp -r ${inputs.noctalia-community-plugins}/agent-glow $out/
    cp -r ${inputs.noctalia-official-plugins}/world_clock $out/
    chmod -R u+w $out
    patch -d $out/agent-glow -p1 < ${./patches/agent-glow-sessions.patch}
    patch -d $out/world_clock -p1 < ${./patches/world-clock-local-zone.patch}
    substituteInPlace $out/world_clock/service.luau \
      --replace-fail '"timedatectl"' '"${pkgs.systemd}/bin/timedatectl"'
  '';

  # Seeded into the world clock's plugin data on every switch; edits made in
  # its panel last until the next switch.
  worldClockZones = pkgs.writeText "world-clock-zones.json" (builtins.toJSON [
    {
      id = "Asia/Singapore";
      label = "🇸🇬";
      on_bar = true;
    }
    {
      id = "America/Los_Angeles";
      label = "🇺🇸";
      on_bar = true;
    }
  ]);
in {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  # v5.2.1 only disables the old .nix path; newer Home Manager uses a directory.
  disabledModules = ["programs/noctalia"];

  # Native Noctalia v5, ported from the legacy v4 settings.json.
  # Changes made in the settings window are written to
  # ~/.local/state/noctalia/settings.toml and take precedence over this file.
  programs.noctalia = {
    enable = true;

    settings = {
      shell = {
        # Emoji second: fontconfig's fallback otherwise reaches Unifont first,
        # which draws flag emoji as boxed letters.
        font_family = "JetBrainsMono NF, Noto Color Emoji";
        avatar_path = "~/.face";
        telemetry_enabled = false;
        # No other polkit agent runs under niri; share-wifi needs one for pkexec.
        polkit_agent = true;
        animation = {
          enabled = true;
          speed = 1.0;
        };
        shadow.direction = "down_right";
        panel = {
          control_center_placement = "attached";
          launcher_position = "center";
        };
        launcher.sort_by_usage = true;
      };

      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };

      wallpaper = {
        enabled = true;
        directory = "~/Pictures/Wallpapers/Walls";
        fill_mode = "crop";
        transition_duration = 1500;
        automation.enabled = false;
      };

      # Replaces the v4 blurred/tinted wallpaper in the niri overview.
      backdrop = {
        enabled = true;
        blur_intensity = 0.5;
        tint_intensity = 0.6;
      };

      location = {
        auto_locate = false;
        address = "Singapore";
      };

      weather = {
        enabled = true;
        unit = "celsius";
        effects = true;
      };

      notification = {
        layer = "overlay";
        background_opacity = 1.0;
      };

      osd = {
        position = "top_right";
        background_opacity = 1.0;
      };

      nightlight = {
        enabled = false;
        temperature_day = 6500;
        temperature_night = 4000;
      };

      bar.default = {
        position = "bottom";
        # v4 "framed" bar: full width, flush with the edge, concave inner corners.
        margin_ends = 0;
        margin_edge = 0;
        concave_edge_corners = true;
        radius = 12;
        background_opacity = 0.93;
        capsule = true;
        # Dense: slimmer bar, tighter padding, slightly smaller icons and text.
        thickness = 30;
        padding = 8;
        widget_spacing = 3;
        capsule_padding = 4;
        scale = 0.9;
        font_scale = 0.75;

        # Related widgets share one capsule; nothing is hidden behind hover.
        # Bluetooth's device label is off to save space; the tooltip shows it.
        # Emoji picker (Mod+;) and night light (control centre) stay off the bar.
        # Everything left-aligned: system entry points and time first, then live
        # stats, then the playful bits that change width.
        start = [
          "control-center"
          "workspaces"
          "group:time"
          "group:sysmon"
          "group:agents"
          "media"
          "bongocat"
        ];
        center = [];
        end = ["group:nix" "privacy" "group:tools" "group:controls" "group:connectivity"];

        # Collapsible groups show their first member until hovered and unfold
        # toward the centre. Privacy stays outside so captures are never hidden.
        capsule_group = [
          {
            id = "time";
            members = ["date" "world-clock"];
            padding = 4;
          }
          {
            id = "sysmon";
            members = ["cpu" "ram" "disk" "net-down" "net-up"];
            padding = 4;
          }
          {
            id = "agents";
            members = ["agent-glow" "claude-usage" "codex-usage"];
            padding = 4;
          }
          {
            id = "nix";
            members = ["nix-status" "nix-monitor"];
            padding = 4;
          }
          {
            id = "tools";
            members = ["ocr" "notifications" "phone" "share-wifi"];
            padding = 4;
            accordion = true;
            accordion_direction = "start";
          }
          {
            id = "controls";
            members = ["volume" "brightness" "battery"];
            padding = 4;
          }
          {
            id = "connectivity";
            members = ["ip" "tailscale" "bluetooth" "network"];
            padding = 4;
          }
        ];
      };

      widget = {
        workspaces = {
          label_source = "id";
          labels_only_when_occupied = true;
          focused_color = "primary";
          occupied_color = "secondary";
          empty_color = "secondary";
        };

        # Glyph + value only (no gauges); percentages instead of GiB figures.
        cpu = {
          type = "sysmon";
          stat = "cpu_usage";
          visualization = "none";
        };
        ram = {
          type = "sysmon";
          stat = "ram_pct";
          visualization = "none";
        };
        disk = {
          type = "sysmon";
          stat = "disk_used_pct";
          path = "/";
          visualization = "none";
        };
        net-down = {
          type = "sysmon";
          stat = "net_rx";
          network_speed_compact = true;
          visualization = "none";
        };
        net-up = {
          type = "sysmon";
          stat = "net_tx";
          network_speed_compact = true;
          visualization = "none";
        };

        # v4 ip-monitor showed the public IP.
        ip = {
          type = "3ri4ng0ld/ip-monitor:widget";
          mode = "custom_command";
          custom_command = "curl -s ifconfig.me";
          refresh_interval = 300;
          glyph_color = "primary";
        };

        control-center = {
          custom_image = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
        };

        media = {
          artist_first = true;
          max_length = 145;
          title_scroll = "on_hover";
          hide_when_no_media = true;
        };

        # Replaces the plain clock: live 🇸🇬 and 🇺🇸 times (plus 📍 local time
        # when elsewhere), panel on click. It shares the "time" capsule with the
        # built-in "date" widget, date first.
        world-clock = {
          type = "noctalia/world_clock:bar";
          show_clocks = true;
        };

        agent-glow = {
          type = "fel/agent-glow:indicator";
        };

        # Reads ~/.claude/.credentials.json and refreshes its OAuth token.
        claude-usage = {
          type = "jrohland/claudecode:pill";
          pill_extras = "countdown";
        };

        # Headroom only reads ~/.codex/auth.json; run `codex` if the session expires.
        codex-usage = {
          type = "ayagmar/headroom:usage";
        };

        nix-status = {
          type = "mindnbytes/nix-status:status";
          color = "secondary";
          icon_color = "primary";
        };

        nix-monitor = {
          type = "avivbintangaringga/nix-monitor:nix-monitor";
          show_text = false;
        };

        # Also the target for the OCR keybind in niri.
        ocr = {
          type = "fel/ocr:ocr";
        };

        # Not on the bar by default; add "emoji" to a lane to show it.
        emoji = {
          type = "liamwh/emoji-picker:widget";
        };

        share-wifi = {
          type = "conqazht/share-wifi:widget";
        };

        bongocat = {
          type = "noctalia/bongocat:cat";
          # keyd grabs the physical keyboards; read its virtual one (udev
          # symlink in base.nix). Reading it relies on the input group.
          input_devices = ["/dev/input/by-id/keyd-virtual-keyboard-event-kbd"];
        };

        privacy.hide_inactive = true;

        notifications.hide_when_no_unread = true;

        bluetooth.show_label = false;

        tailscale = {
          type = "davemhammer/tailscale:status";
        };

        phone = {
          type = "icefish/phone-connect:bar";
        };

        volume.actions.middle = "exec pwvucontrol || pavucontrol";

        battery.display_mode = "glyph";
      };

      dock = {
        enabled = true;
        position = "bottom";
        auto_hide = true;
        reserve_space = false;
        margin_edge = 8;
        active_monitor_only = true;
        show_dots = false;
        background_opacity = 1.0;
      };

      control_center.shortcuts = [
        {type = "wifi";}
        {type = "bluetooth";}
        {type = "notification";}
        {type = "caffeine";}
        {type = "nightlight";}
        {type = "wallpaper";}
      ];

      plugins = {
        enabled = [
          "3ri4ng0ld/ip-monitor"
          "noctalia/bongocat"
          "davemhammer/tailscale"
          "icefish/phone-connect"
          "mindnbytes/nix-status"
          "knyrps/nix-search"
          "noctalia/world_clock"
          "kenn/keybind-cheatsheet"
          "avivbintangaringga/nix-monitor"
          "fel/ocr"
          "liamwh/emoji-picker"
          "conqazht/share-wifi"
          "fel/agent-glow"
          "jrohland/claudecode"
          "ayagmar/headroom"
        ];
        auto_update = "all";

        # The git sources stay for browsing/trying plugins in the settings window.
        # Later sources take precedence, so the Nix-pinned copies win for enabled
        # plugins; bump them with `nix flake update noctalia-community-plugins`.
        source = [
          {
            name = "official";
            kind = "git";
            location = "https://github.com/noctalia-dev/official-plugins";
            enabled = true;
          }
          {
            name = "community";
            kind = "git";
            location = "https://github.com/noctalia-dev/community-plugins";
            enabled = true;
          }
          {
            name = "nix-official";
            kind = "path";
            location = "${inputs.noctalia-official-plugins}";
            enabled = true;
          }
          {
            name = "nix-community";
            kind = "path";
            location = "${inputs.noctalia-community-plugins}";
            enabled = true;
          }
          {
            name = "nix-patched";
            kind = "path";
            location = "${patchedPlugins}";
            enabled = true;
          }
        ];
      };

      plugin_settings = {
        "mindnbytes/nix-status" = {
          flake_dir = "${config.home.homeDirectory}/dotnix";
          # nixosConfigurations names match the hostnames.
          nixos_configuration = osConfig.networking.hostName;
          use_themed_logos = false;
        };
        "avivbintangaringga/nix-monitor" = {
          branch = "nixos-unstable";
          # Updates every flake input in flake.lock, then switches.
          update_command = "nh os switch --update ${config.home.homeDirectory}/dotnix -H ${osConfig.networking.hostName}";
        };
        # Types the picked character into the focused window after copying it.
        "liamwh/emoji-picker".paste_command = "wtype {emoji}";
        # Codex only, as a plain percentage; Claude is in Headroom's panel since
        # claudecode already shows it on the bar.
        "ayagmar/headroom" = {
          provider_codex = "bar";
          provider_claude = "panel";
          provider_antigravity = "off";
          window = "session";
          bar_style = "value";
        };
        # Setting this (re)starts the world clock service, which loads the
        # SG/SF labels seeded below.
        "noctalia/world_clock".time_format = "24h";
        "fel/agent-glow".agents = "opencode,claude,codex,gemini,aider,goose,paseo";
        "kenn/keybind-cheatsheet" = {
          compositor = "niri";
          niri_config = "~/.config/niri/config.kdl";
        };
      };
    };
  };

  home.activation.noctaliaWorldClockZones = lib.hm.dag.entryAfter ["writeBoundary"] ''
    dir="${config.xdg.stateHome}/noctalia/plugins/data/noctalia/world_clock"
    run mkdir -p "$dir"
    run install -m 644 ${worldClockZones} "$dir/zones.json"
  '';

  services.kdeconnect.enable = true;

  # Runtime dependencies for the enabled plugins.
  home.packages = with pkgs; [
    curl # ip-monitor
    jq # tailscale
    sshfs # phone-connect file browsing
    nix-search-tv # nix-search
    fzf # nix-search
    grim # ocr
    slurp # ocr
    tesseract # ocr
    wtype # emoji-picker
    evtest # bongocat
    linux-wifi-hotspot # share-wifi (create_ap)
    iw # share-wifi
    python3 # agent-glow
  ];
}
