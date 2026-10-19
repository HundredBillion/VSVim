# One Dark syntax

VSVim’s default `vsvim-one-dark` uses the syntax colors from
[Zed’s built-in One Dark theme](https://github.com/zed-industries/zed/blob/main/assets/themes/one/one.json).
The charcoal window colors and native tabs/sidebar retain the existing JB palette.
The previous complete palette remains available as `:colorscheme vsvim-jb-dark`.

| Syntax | Color |
| --- | --- |
| Keywords (`const`, `fn`, `let`, `for`, `return`) | Purple `#b477cf` |
| Functions and constructors | Blue `#73ade9` |
| Types and operators | Teal `#6eb4bf` |
| Strings | Green `#a1c181` |
| Constants | Yellow `#dfc184` |
| Properties and parameters | Red `#d07277` |
| Numbers and booleans | Brown `#bf956a` |
| Comments / documentation | Gray `#5d636f` / `#878e98` |

The colors apply to traditional syntax groups, Tree-sitter captures, and LSP
semantic tokens. Neovim and Zed classify some tokens differently; this maps their
syntax categories rather than reproducing Zed’s highlighting engine. The minimap
uses the editor’s resolved colors and refreshes when the colorscheme changes.

Use `:colorscheme vsvim-one-dark` to reload it. To choose another theme permanently,
put your `vim.cmd('colorscheme ...')` in VSVim’s `user.lua`.

Verify palette and actual Rust keyword rendering with:

```sh
nvim --clean --headless '+lua local ok,e=pcall(dofile,"tests/one_dark.lua"); if not ok then print(e); vim.cmd("cquit 1") end' '+qa!'
```
