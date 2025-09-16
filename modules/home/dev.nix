# DevTools
{pkgs, ...}: {
  home.packages = with pkgs; [
    # gcc
    # libnfc
    # python312
    aider-chat-full
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
