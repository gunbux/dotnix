# DevTools
{pkgs, ...}: {
  home.packages = with pkgs; [
    # gcc
    # libnfc
    # python312
    # aider-chat-full
    # marksman
    bun
    cargo
    conda
    geekbench
    ghostscript_headless
    gnumake
    lua-language-server
    logiops
    meson
    ninja
    nodejs
    rust-analyzer
    rustfmt
    tree-sitter
    tshark
    uv
    zls
  ];
}
