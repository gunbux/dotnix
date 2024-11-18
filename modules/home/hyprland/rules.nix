{ config, lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    windowrulev2 = [
      # Picture-in-Picture rules
      "keepaspectratio, title:^(Picture(-| )in(-| )[Pp]icture)$"
      "move 73% 72%, title:^(Picture(-| )in(-| )[Pp]icture)$"
      "size 25%, title:^(Picture(-| )in(-| )[Pp]icture)$"
      "float, title:^(Picture(-| )in(-| )[Pp]icture)$"
      "pin, title:^(Picture(-| )in(-| )[Pp]icture)$"
    ];

    windowrule = [
      # Dialog rules
      "float,title:^(Open File)(.*)$"
      "float,title:^(Select a File)(.*)$"
      "float,title:^(Choose wallpaper)(.*)$"
      "float,title:^(Open Folder)(.*)$"
      "float,title:^(Save As)(.*)$"
      "float,title:^(Library)(.*)$"
      "float,title:^(File Upload)(.*)$"
      
      # Workspace rules
      "workspace 2 silent,vivaldi"
      "workspace 3 silent,spotify"
      "workspace 4 silent,cursor"
    ];
  };
}