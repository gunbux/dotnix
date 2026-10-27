# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

Home Manager loads its provider bootstrap before this configuration with
`programs.neovim.sideloadInitLua`. Python and Ruby hosts come from Nix; unused
Node and Perl hosts are explicitly disabled by that bootstrap.

WakaTime starts when `WAKATIME_API_KEY` is set, or when you set
`vim.g.wakatime_enabled = true` in `lua/config/options.lua` for credentials already
stored in `~/.wakatime.cfg`. No key belongs in this repository. Without credentials,
time tracking remains inactive rather than emitting repeated startup warnings.

Snacks image previews use ImageMagick from Neovim's Nix runtime dependencies and
Ghostty from the macOS application bundle. Open Neovim in Ghostty for image support.
Additional document parsers install on first startup. Nix supplies `tectonic` for
LaTeX math and `mmdc` for Mermaid diagrams. On macOS, Mermaid uses the installed
Google Chrome application; on Linux it uses Nix's Chromium. Tectonic may download
its TeX bundle when first rendering a formula. The current nvim-treesitter release
does not include a Norg parser, so Snacks can report that optional document format
as unavailable.

Run `:checkhealth` inside a terminal after startup. Headless checks cannot verify
terminal graphics or UI components such as the dashboard and notifier. An available
newer Neovim patch release is informational; updating the shared Nix pin is a separate
dependency change.

Markdown and Vimwiki `.md` files open in md-render.nvim's experimental auto mode.
Normal mode shows the rendered document. Press `i`, `I`, `a`, `A`, `o`, or `O` to
edit the corresponding source line, then Escape to render again. `:w` and `:w!`
save the Markdown source even while viewing the rendered document.

- `<leader>ma` toggles auto mode. Turning it off returns to ordinary source editing.
- `<leader>mr` switches between source and rendered views in the same window.
- `<leader>ms` opens source and rendered views in a vertical split.
- `<leader>md` opens the renderer's demo.

The rendered buffer is read-only. Switch to source with `<leader>mr` for Normal
mode edits such as `dd`, paste, undo/redo, substitutions, macros, or saving to a
different filename. Turn auto mode off with `<leader>ma` to stay in source mode
after leaving Insert. This is source/render switching rather than direct editing
of formatted text, and cursor mapping follows source lines.

md-render.nvim requires Neovim 0.12 or newer. Inline images need a terminal with
the Kitty graphics protocol, such as Ghostty. ImageMagick and Mermaid CLI are
already supplied by the Neovim Nix module. After deploying this configuration,
run `:Lazy sync` to install the replacement and remove render-markdown.nvim.
