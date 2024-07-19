# Generated via dconf2nix: https://github.com/gvolpe/dconf2nix
{ lib, ... }:

with lib.hm.gvariant;

{
  dconf.settings = {
    "org/gnome/Console" = {
      font-scale = 1.2;
      last-window-size = mkTuple [ 1080 1033 ];
    };

    "org/gnome/Geary" = {
      migrated-config = true;
      window-height = 1224;
      window-width = 1012;
    };

    "org/gnome/Totem" = {
      active-plugins = [ "open-directory" "screenshot" "vimeo" "apple-trailers" "recent" "movie-properties" "screensaver" "autoload-subtitles" "save-file" "skipto" "mpris" "rotation" "variable-rate" ];
      subtitle-encoding = "UTF-8";
    };

    "org/gnome/baobab/ui" = {
      is-maximized = false;
      window-size = mkTuple [ 2032 1232 ];
    };

    "org/gnome/cheese" = {
      burst-delay = 1000;
      camera = "USB2.0 HD UVC WebCam (V4L2)";
      photo-x-resolution = 1280;
      photo-y-resolution = 720;
      video-x-resolution = 1280;
      video-y-resolution = 720;
    };

    "org/gnome/control-center" = {
      last-panel = "keyboard";
      window-state = mkTuple [ 840 1020 ];
    };

    "org/gnome/desktop/a11y/interface" = {
      high-contrast = false;
    };

    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Utilities" "YaST" ];
    };

    "org/gnome/desktop/app-folders/folders/Utilities" = {
      apps = [ "gnome-abrt.desktop" "gnome-system-log.desktop" "nm-connection-editor.desktop" "org.gnome.baobab.desktop" "org.gnome.Connections.desktop" "org.gnome.DejaDup.desktop" "org.gnome.Dictionary.desktop" "org.gnome.DiskUtility.desktop" "org.gnome.eog.desktop" "org.gnome.Evince.desktop" "org.gnome.FileRoller.desktop" "org.gnome.fonts.desktop" "org.gnome.seahorse.Application.desktop" "org.gnome.tweaks.desktop" "org.gnome.Usage.desktop" "vinagre.desktop" ];
      categories = [ "X-GNOME-Utilities" ];
      name = "X-GNOME-Utilities.directory";
      translate = true;
    };

    "org/gnome/desktop/app-folders/folders/YaST" = {
      categories = [ "X-SuSE-YaST" ];
      name = "suse-yast.directory";
      translate = true;
    };

    "org/gnome/desktop/background" = {
      color-shading-type = "solid";
      picture-options = "zoom";
      picture-uri = "file:///run/current-system/sw/share/backgrounds/gnome/amber-l.jxl";
      picture-uri-dark = "file:///run/current-system/sw/share/backgrounds/gnome/amber-d.jxl";
      primary-color = "#3071AE";
      secondary-color = "#000000";
    };

    "org/gnome/desktop/input-sources" = {
      show-all-sources = true;
      sources = [ (mkTuple [ "xkb" "us" ]) ];
      xkb-options = [ "terminate:ctrl_alt_bksp" "caps:swapescape" ];
    };

    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      color-scheme = "prefer-dark";
      cursor-size = 30;
      cursor-theme = "Nordzy-cursors-white";
      document-font-name = "Source Sans 3 11";
      enable-animations = true;
      font-antialiasing = "grayscale";
      font-hinting = "slight";
      font-name = "Source Sans 3 11";
      gtk-theme = "pop-dark";
      icon-theme = "Tela";
      monospace-font-name = "JetBrainsMono Nerd Font 10";
      show-battery-percentage = true;
    };

    "org/gnome/desktop/notifications" = {
      application-children = [ "gnome-power-panel" "org-gnome-settings" "org-gnome-console" "org-gnome-characters" "org-gnome-tweaks" "rog-control-center" "vivaldi-stable" "org-qbittorrent-qbittorrent" "discord" ];
    };

    "org/gnome/desktop/notifications/application/discord" = {
      application-id = "discord.desktop";
    };

    "org/gnome/desktop/notifications/application/gnome-network-panel" = {
      application-id = "gnome-network-panel.desktop";
    };

    "org/gnome/desktop/notifications/application/gnome-power-panel" = {
      application-id = "gnome-power-panel.desktop";
    };

    "org/gnome/desktop/notifications/application/org-gnome-characters" = {
      application-id = "org.gnome.Characters.desktop";
    };

    "org/gnome/desktop/notifications/application/org-gnome-console" = {
      application-id = "org.gnome.Console.desktop";
    };

    "org/gnome/desktop/notifications/application/org-gnome-settings" = {
      application-id = "org.gnome.Settings.desktop";
    };

    "org/gnome/desktop/notifications/application/org-gnome-tweaks" = {
      application-id = "org.gnome.tweaks.desktop";
    };

    "org/gnome/desktop/notifications/application/org-qbittorrent-qbittorrent" = {
      application-id = "org.qbittorrent.qBittorrent.desktop";
    };

    "org/gnome/desktop/notifications/application/rog-control-center" = {
      application-id = "rog-control-center.desktop";
    };

    "org/gnome/desktop/notifications/application/vivaldi-stable" = {
      application-id = "vivaldi-stable.desktop";
    };

    "org/gnome/desktop/peripherals/mouse" = {
      natural-scroll = false;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = true;
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/desktop/screensaver" = {
      color-shading-type = "solid";
      picture-options = "zoom";
      picture-uri = "file:///run/current-system/sw/share/backgrounds/gnome/amber-l.jxl";
      primary-color = "#3071AE";
      secondary-color = "#000000";
    };

    "org/gnome/desktop/search-providers" = {
      sort-order = [ "org.gnome.Contacts.desktop" "org.gnome.Documents.desktop" "org.gnome.Nautilus.desktop" ];
    };

    "org/gnome/desktop/session" = {
      idle-delay = mkUint32 300;
    };

    "org/gnome/desktop/sound" = {
      allow-volume-above-100-percent = true;
    };

    "org/gnome/desktop/wm/keybindings" = {
      minimize = [];
      move-to-monitor-down = [ "<Control><Super>j" ];
      move-to-monitor-left = [ "<Control><Super>h" ];
      move-to-monitor-right = [ "<Control><Super>l" ];
      move-to-monitor-up = [ "<Control><Super>k" ];
      move-to-workspace-left = [ "<Shift><Control><Super>h" ];
      move-to-workspace-right = [ "<Shift><Control><Super>l" ];
      switch-to-workspace-left = [ "<Shift><Super>h" ];
      switch-to-workspace-right = [ "<Shift><Super>l" ];
    };

    "org/gnome/desktop/wm/preferences" = {
      workspace-names = [ "Main" ];
    };

    "org/gnome/epiphany" = {
      ask-for-default = false;
    };

    "org/gnome/epiphany/state" = {
      is-maximized = false;
      window-size = mkTuple [ 1012 1033 ];
    };

    "org/gnome/evolution-data-server" = {
      migrated = true;
    };

    "org/gnome/file-roller/listing" = {
      list-mode = "as-folder";
      name-column-width = 250;
      show-path = false;
      sort-method = "time";
      sort-type = "descending";
    };

    "org/gnome/file-roller/ui" = {
      sidebar-width = 200;
      window-height = 480;
      window-width = 600;
    };

    "org/gnome/gnome-system-monitor" = {
      current-tab = "resources";
      maximized = false;
      network-total-in-bits = false;
      show-dependencies = false;
      show-whose-processes = "user";
      window-state = mkTuple [ 1012 1033 ];
    };

    "org/gnome/gnome-system-monitor/disktreenew" = {
      col-6-visible = true;
      col-6-width = 0;
    };

    "org/gnome/mutter" = {
      center-new-windows = true;
      edge-tiling = false;
    };

    "org/gnome/nautilus/preferences" = {
      default-folder-viewer = "icon-view";
      migrated-gtk-settings = true;
      search-filter-time-type = "last_modified";
      search-view = "list-view";
    };

    "org/gnome/nautilus/window-state" = {
      initial-size = mkTuple [ 1012 1224 ];
    };

    "org/gnome/nm-applet/eap/c1aa27da-8230-407d-a915-4906f2b7193f" = {
      ignore-ca-cert = true;
      ignore-phase2-ca-cert = false;
    };

    "org/gnome/photos" = {
      window-maximized = true;
    };

    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = false;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [ "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" ];
      help = [];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Super>Return";
      command = "kgx";
      name = "Launch Console";
    };

    "org/gnome/shell" = {
      command-history = [ "lg" ];
      disable-user-extensions = false;
      disabled-extensions = [ "workspace-indicator@gnome-shell-extensions.gcampax.github.com" "apps-menu@gnome-shell-extensions.gcampax.github.com" "auto-move-windows@gnome-shell-extensions.gcampax.github.com" "pop-launcher-super-key@ManeLippert" "pop-shell@system76.com" "window-list@gnome-shell-extensions.gcampax.github.com" "drive-menu@gnome-shell-extensions.gcampax.github.com" "places-menu@gnome-shell-extensions.gcampax.github.com" "native-window-placement@gnome-shell-extensions.gcampax.github.com" "windowsNavigator@gnome-shell-extensions.gcampax.github.com" ];
      enabled-extensions = [ "blur-my-shell@aunetx" "launch-new-instance@gnome-shell-extensions.gcampax.github.com" "Vitals@CoreCoding.com" "gsconnect@andyholmes.github.io" "supergfxctl-gex@asus-linux.org" "quick-settings-avatar@d-go" "forge@jmmaranan.com" "just-perfection-desktop@just-perfection" "space-bar@luchrioh" ];
      favorite-apps = [ "org.gnome.Console.desktop" "org.gnome.Nautilus.desktop" "spotify.desktop" "discord.desktop" "vivaldi-stable.desktop" ];
      last-selected-power-profile = "power-saver";
      looking-glass-history = [ "exit" "quit" "ls" ];
      welcome-dialog-last-shown-version = "44.2";
    };

    "org/gnome/shell/extensions/blur-my-shell" = {
      hacks-level = 3;
    };

    "org/gnome/shell/extensions/blur-my-shell/applications" = {
      opacity = 230;
      whitelist = [];
    };

    "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
      blur = true;
    };

    "org/gnome/shell/extensions/forge" = {
      css-last-update = mkUint32 37;
      focus-border-toggle = false;
      tiling-mode-enabled = false;
      window-gap-hidden-on-single = true;
      workspace-skip-tile = "";
    };

    "org/gnome/shell/extensions/forge/keybindings" = {
      con-split-horizontal = [ "<Super>z" ];
      con-split-layout-toggle = [ "<Super>g" ];
      con-split-vertical = [ "<Super>v" ];
      con-stacked-layout-toggle = [ "<Shift><Super>s" ];
      con-tabbed-layout-toggle = [ "<Shift><Super>t" ];
      con-tabbed-showtab-decoration-toggle = [ "<Control><Alt>y" ];
      focus-border-toggle = [ "<Super>x" ];
      mod-mask-mouse-tile = "Alt";
      prefs-tiling-toggle = [ "<Super>w" ];
      window-focus-down = [ "<Super>j" ];
      window-focus-left = [ "<Super>h" ];
      window-focus-right = [ "<Super>l" ];
      window-focus-up = [ "<Super>k" ];
      window-gap-size-decrease = [ "<Control><Super>minus" ];
      window-gap-size-increase = [ "<Control><Super>plus" ];
      window-move-down = [ "<Shift><Alt><Super>j" ];
      window-move-left = [ "<Shift><Alt><Super>h" ];
      window-move-right = [ "<Shift><Alt><Super>l" ];
      window-move-up = [ "<Shift><Alt><Super>k" ];
      window-resize-bottom-decrease = [ "<Shift><Control><Super>i" ];
      window-resize-bottom-increase = [ "<Control><Super>u" ];
      window-resize-left-decrease = [ "<Shift><Control><Super>o" ];
      window-resize-left-increase = [ "<Control><Super>y" ];
      window-resize-right-decrease = [ "<Shift><Control><Super>y" ];
      window-resize-right-increase = [ "<Control><Super>o" ];
      window-resize-top-decrease = [ "<Shift><Control><Super>u" ];
      window-resize-top-increase = [ "<Control><Super>i" ];
      window-snap-center = [ "<Control><Alt>c" ];
      window-snap-one-third-left = [ "<Control><Alt>d" ];
      window-snap-one-third-right = [ "<Control><Alt>g" ];
      window-snap-two-third-left = [ "<Control><Alt>e" ];
      window-snap-two-third-right = [ "<Control><Alt>t" ];
      window-swap-down = [ "<Control><Super>j" ];
      window-swap-last-active = [ "<Shift><Super>Return" ];
      window-swap-left = [ "<Control><Super>h" ];
      window-swap-right = [ "<Control><Super>l" ];
      window-swap-up = [ "<Control><Super>k" ];
      window-toggle-always-float = [ "<Shift><Super>c" ];
      window-toggle-float = [ "<Super>c" ];
      workspace-active-tile-toggle = [ "<Shift><Super>w" ];
    };

    "org/gnome/shell/extensions/gsconnect" = {
      enabled = false;
      id = "b1c3bb93-fd98-4d6e-9a35-fe513a7027e7";
      name = "chun-lappy";
    };

    "org/gnome/shell/extensions/gsconnect/preferences" = {
      window-maximized = false;
      window-size = mkTuple [ 640 440 ];
    };

    "org/gnome/shell/extensions/just-perfection" = {
      accessibility-menu = false;
      animation = 4;
      app-menu = false;
      app-menu-icon = false;
      background-menu = true;
      clock-menu = true;
      controls-manager-spacing-size = 0;
      dash = true;
      dash-icon-size = 32;
      double-super-to-appgrid = true;
      gesture = true;
      hot-corner = true;
      osd = true;
      panel = true;
      panel-arrow = false;
      panel-corner-size = 1;
      panel-in-overview = true;
      ripple-box = false;
      search = false;
      show-apps-button = false;
      startup-status = 0;
      theme = false;
      top-panel-position = 0;
      window-demands-attention-focus = true;
      window-picker-icon = false;
      window-preview-caption = true;
      window-preview-close-button = true;
      workspace = false;
      workspace-background-corner-size = 0;
      workspace-popup = true;
      workspaces-in-app-grid = false;
    };

    "org/gnome/shell/extensions/pano" = {
      history-length = 50;
      sync-primary = false;
    };

    "org/gnome/shell/extensions/pop-shell" = {
      active-hint = false;
      smart-gaps = true;
      tile-by-default = true;
    };

    "org/gnome/shell/extensions/space-bar/shortcuts" = {
      enable-activate-workspace-shortcuts = false;
    };

    "org/gnome/shell/extensions/unite" = {
      autofocus-windows = true;
      enable-titlebar-actions = true;
      extend-left-box = false;
      hide-activities-button = "always";
      hide-app-menu-icon = true;
      hide-dropdown-arrows = true;
      hide-window-titlebars = "always";
      reduce-panel-spacing = false;
      show-desktop-name = true;
      show-legacy-tray = false;
    };

    "org/gnome/shell/extensions/user-theme" = {
      name = "pop-dark";
    };

    "org/gnome/shell/extensions/vitals" = {
      alphabetize = true;
      hide-icons = false;
      hide-zeros = true;
      hot-sensors = [ "_system_load_1m_" "__network-rx_max__" "_battery_rate_" "_battery_time_left_" "_network_public_ip_" ];
      show-battery = true;
      show-voltage = true;
      use-higher-precision = true;
    };

    "org/gnome/shell/world-clocks" = {
      locations = "@av []";
    };

    "org/gnome/terminal/legacy" = {
      always-check-default-terminal = true;
    };

    "org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9" = {
      background-color = "rgb(23,20,33)";
      foreground-color = "rgb(208,207,204)";
      palette = [ "rgb(23,20,33)" "rgb(192,28,40)" "rgb(38,162,105)" "rgb(162,115,76)" "rgb(18,72,139)" "rgb(163,71,186)" "rgb(42,161,179)" "rgb(208,207,204)" "rgb(94,92,100)" "rgb(246,97,81)" "rgb(51,209,122)" "rgb(233,173,12)" "rgb(42,123,222)" "rgb(192,97,203)" "rgb(51,199,222)" "rgb(255,255,255)" ];
      use-theme-colors = false;
    };

    "org/gnome/tweaks" = {
      show-extensions-notice = false;
    };

    "org/gtk/gtk4/settings/file-chooser" = {
      date-format = "regular";
      location-mode = "path-bar";
      show-hidden = true;
      show-size-column = true;
      show-type-column = true;
      sidebar-width = 140;
      sort-column = "name";
      sort-directories-first = false;
      sort-order = "ascending";
      type-format = "category";
      view-type = "list";
      window-size = mkTuple [ 793 720 ];
    };

    "org/gtk/settings/file-chooser" = {
      clock-format = "12h";
    };

  };
}
