# DevTools
{pkgs, ...}: {
  home.packages = with pkgs; [
    # aider-chat-full
    # gcc
    # geekbench
    # libnfc
    # marksman
    alejandra
    bun
    cargo
    clang
    clang-tools
    conda
    ghostscript_headless
    gnumake
    kdlfmt
    lua-language-server
    meson
    ninja
    nodejs
    python3
    rust-analyzer
    rustfmt
    tree-sitter
    tshark
    uv
    zls
  ];
}
