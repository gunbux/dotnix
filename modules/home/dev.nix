# DevTools
{pkgs, ...}: {
  home.packages = with pkgs; [
    # AI
    # aider-chat-full
    # gcc
    # libnfc
    # python312
    bun
    cargo
    conda
    geekbench
    ghostscript_headless
    gnumake
    lua-language-server
    logiops
    marksman
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
