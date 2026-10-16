# VSVim

An independent Neovim distribution for reading and reviewing agent-written code.

This development milestone provides isolated startup and the svgtree explorer.
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

The Sprite plugin API is bundled, and svgtree chooses its native explorer when
the host supports it. This milestone does not yet launch Neovim through Sprite's
native grid adapter or implement the complete VS Code visual design.

## Development checks

Run `python3 -m unittest discover -s tests -p '*_test.py'` with Neovim nightly
and Git on PATH. Integration checks download pinned plugins into a temporary
profile, verify the explorer and user overrides, then check cached startup
without Git. They do not use your normal Neovim configuration.

Tested locally on macOS with Neovim `0.13.0-dev-761+g0639f6e41a`. Linux runtime
validation and native Sprite visual acceptance have not run for this milestone.
Plugin revisions are fixed in the distribution; `:Lazy sync` preserves those
revisions. Updates to bundled versions ship as changes to VSVim's pins.
