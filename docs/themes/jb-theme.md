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
native grid font through `[surface_font]`; `[font]` controls the terminal, including
Neovim running as an ordinary terminal program. The bundled `extras/sprite-jb.toml`
uses Menlo 12 for both sections. Native editor rows use a 1.65 line-height ratio
(20-pixel rows) for more breathing room; terminal rows use 1.5 (18 pixels).
Choose an installed monospace family on Linux.

To change native editor text independently, edit `[surface_font]` and reload
Sprite's configuration. Removing the entire section makes native grids inherit
`[font]`. An explicit section uses Sprite's font defaults for omitted fields:
a discovered monospace family, size 14, and line height 8/7. Window zoom adds the
same size delta to both configured fonts; reset restores both configured sizes.
Native sidebar and other UI labels retain their system UI font.

Code wrapping is disabled by default; use `:set wrap` to enable it.

The previous theme remains available as `:colorscheme vsvim-dark-modern`.
