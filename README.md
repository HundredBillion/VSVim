# VSVim

An independent Neovim distribution for reading and reviewing agent-written code.

This development milestone provides isolated startup, a VS Code Dark Modern
theme, file tabs, status line, and the svgtree explorer.
PR review, agent following, and the reviewer conversation are not implemented yet.

## Run from a checkout

Install Neovim 0.13 nightly and Git, then run `./bin/vsvim` from this checkout.
The launcher uses `nvim-nightly`; set `VSVIM_NVIM` to an alternate nightly executable.
The first launch downloads pinned plugins. Later launches reuse them.
The launcher can also be placed on PATH through a symlink to `bin/vsvim`.

VSVim uses the `vsvim` Neovim application namespace and leaves the ordinary
`nvim` configuration in place. Run `:echo stdpath('config')` to find VSVim's
configuration directory. Create `user.lua` there for settings loaded after defaults.

## Controls

Use normal Neovim editing modes. Space is the leader. Press Space then e,
or Ctrl-b, to toggle the explorer. `:SvgTreeToggle` is also available.

## Sprite

Inside an eligible Sprite pane, the launcher automatically starts the native
editor adapter using the same Neovim nightly binary. On first launch it installs
the adapter before opening the editor. Other terminals retain normal Neovim
rendering. Set `VSVIM_NATIVE=0` to force the terminal path. Headless, embedded,
script, help, and version invocations bypass the native adapter.

The palette follows VS Code Dark Modern: dark gray editor, darker sidebar and
tabs, blue mode accent, and familiar syntax colors. Click file tabs to switch
buffers. The explorer opens by default in interactive sessions; put
`vim.g.vsvim_auto_explorer = false` in `user.lua` to disable that behavior.
User overrides run after appearance setup, so a different colorscheme can be
selected there.

Sprite controls font metrics and native panel geometry. This is an initial
visual implementation, not a claim of pixel-identical VS Code rendering.

## Development checks

Run `python3 -m unittest discover -s tests -p '*_test.py'` with Neovim nightly
and Git on PATH. Integration checks download pinned plugins into a temporary
profile, verify the explorer and user overrides, then check cached startup
without Git. They do not use your normal Neovim configuration.

Tested locally on macOS with Neovim `0.13.0-dev-761+g0639f6e41a`. Linux runtime
validation has not run. Native Sprite startup was exercised, but screenshot
comparison is still pending because macOS denied window capture.
Plugin revisions are fixed in the distribution; `:Lazy sync` preserves those
revisions. Updates to bundled versions ship as changes to VSVim's pins.
