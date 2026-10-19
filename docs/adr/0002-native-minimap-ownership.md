# Keep minimap editor state in VSVim and native rendering in Sprite

The user approved the miniature-code minimap and overlays for VSVim. VSVim owns
source lines, colors, changes and selections; sprite.nvim transports a negotiated
extension; Sprite owns native glyph rendering and pointer geometry. The existing
Neovim redraw grid only contains visible editor cells, so shrinking that grid
would omit offscreen source. A browser renderer would introduce another UI
runtime; a character-pattern terminal minimap would not match the approved design.

A real Neovim 0.13 probe showed that retaining a Visual cursor while setting
`topline` far away snaps the view back to the cursor. The user explicitly chose
preserved selection while browsing: VSVim captures and displays that selection,
then restores it before keyboard input. This extra behavior is required for
VS Code-like browsing without changing default Vim key meanings.
