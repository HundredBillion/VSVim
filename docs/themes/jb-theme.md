# JetBrains Dark Theme

VSVim's default `vsvim-jb-dark` translates the active **JetBrains Dark Theme**
from `kenethriera.jb-theme` version 1.0.35. Source: the installed extension's
`themes/generated/jetbrains-dark-color_theme.json`.
Upstream: https://github.com/rierarizzo/jetbrains-theme (CC0-1.0).

Editor #1e1f22; sidebar/status #2b2d30; comments #7a7e85; strings #6aab73;
keywords #cf8e6d; functions #56a8f5; numbers #2aacb8; properties #c77dbb.
Neovim highlight groups approximate TextMate scopes; language-specific token
rules are not an exact one-to-one mapping. UI colors not specified by JB Theme
retain the existing VS Code-style defaults.

The extension specifies no font. With no VS Code font override, macOS uses
Menlo 12; Linux uses Droid Sans Mono 14 with monospace fallback. Sprite owns the
editor font; Neovim cannot change an ordinary terminal's font. The bundled
`extras/sprite-jb.toml` selects Menlo 12 with a 1.5 line-height ratio (18-pixel rows), matching VS Code
on macOS. Code wrapping is disabled by default; use `:set wrap` to enable it. Choose an installed
monospace family on Linux. Native sidebar text retains the system UI font,
matching VS Code's workbench.

The previous theme remains available as `:colorscheme vsvim-dark-modern`.
