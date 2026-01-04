{pkgs, ...}: {
  home.packages = with pkgs; [
    # AMD specific packages
    amdgpu_top
  ];
}
