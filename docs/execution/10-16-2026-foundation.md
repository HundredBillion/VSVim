# Foundation execution

Implemented the isolated-foundation TSP on `feat/foundation`, starting at
`ec1c7d2`. This is milestone 1a, not the complete VSVim release.

## Delivered

- `bin/vsvim` selects `nvim-nightly` or `VSVIM_NVIM`, uses the `vsvim`
  application namespace, and preserves arguments, working directory, and exit status.
- Startup requires Neovim 0.13 and `vim.ui.img`.
- Pinned lazy.nvim, sprite.nvim, and SVGTree install under VSVim's data directory.
- Space-e and Ctrl-b toggle the explorer; external `user.lua` loads after defaults.
- Failed runtime/bootstrap/required-plugin checks terminate with an error.

## Changes discovered during execution

The stable lazy.nvim tag resolves to commit
`85c7ff3711b730b4030d03144f6db6375044ae82`. Pinning bootstrap alone was insufficient:
`:Lazy sync` updated the manager. An explicit self-spec now preserves its revision.

Neovim can print initialization errors and exit zero when subsequently given
`+qa`. Startup errors now explicitly exit nonzero. Missing Git is caught and
reported with bootstrap context. The regression failed before this change.

Independent review found that lazy.nvim absorbs missing-plugin installation
errors. VSVim now verifies its required public APIs and explorer command after
setup. A simulated failed clone reproduced exit zero before the fix and now
exits nonzero. Review also prompted a symlink-chain regression test.

## Evidence

- Python unittest discovery: three tests pass, including fresh downloads,
  exact installed revisions after sync, overrides, isolated standard paths,
  cached startup without Git, failed bootstrap, and failed required-plugin clones.
- Launcher checks preserve arguments/exit status and resolve a mixed symlink chain
  through a directory containing spaces.
- Real editor smoke opens/closes SVGTree through its command.
- Interactive terminal check: Space-e opens the explorer; Ctrl-b closes it;
  `:qa!` exits successfully.
- Stable Neovim 0.12.6 is rejected with an explicit requirement for 0.13 nightly.
- Shell syntax and Git whitespace checks pass.

Runtime: macOS, Neovim `0.13.0-dev-761+g0639f6e41a`. Linux runtime and native
Sprite visual acceptance are not yet verified. Existing ordinary Neovim
configuration and sibling plugin repositories were not modified.

SCM replacement, the rest of the editing defaults, prism.nvim, agent-follow,
reviewer integrations, and native editor presentation remain separate milestones.

## Dark Modern and native Sprite follow-up

The user approved moving directly to the visual slice after trying the initial
foundation. This bounded change uses the existing Sprite adapter and SVGTree
interfaces rather than adding a rendering framework.

- Palette reference: VS Code `extensions/theme-defaults/themes/dark_modern.json`,
  with inherited Dark+ syntax colors, inspected from the local VS Code source.
- Added a reloadable colorscheme, clickable file tabs, compact status line, and
  automatic interactive explorer opening. User configuration remains last.
- Sprite sessions launch the installed adapter with the selected nightly binary.
  First-use bootstrap installs the adapter before starting it. Noninteractive
  and nested Neovim invocations retain the terminal path. `VSVIM_NATIVE=0`
  explicitly disables the adapter.
- Lazy runtime-path reset initially hid the new appearance module; including
  the distro root in lazy's runtime paths fixed the observed startup failure.
- Four automated tests pass, including native-route argument forwarding and
  evaluated tab rendering with percent signs in filenames, buffer selection,
  colorscheme reloading, and opening/closing the terminal explorer.
- A real Sprite test window reports `g:sprite_session` present, the Dark Modern
  colorscheme active, and SVGTree's public root set to the demo workspace.
- macOS window screenshot capture returned `could not create image from window`.
  No screenshot-based fidelity claim is made. Native font metrics, tab border
  geometry, activity rail, and full VS Code layout remain visual follow-up work.

Visual follow-up review identified a tab-selection error in split editors.
Commit `e3d3ab6` preserves the current ordinary editor window and uses a fallback
only from sidebar focus. The right-split regression failed before the fix and
passed afterward; independent re-review found no remaining Important issues.
Final suite: four tests passed in 14.580 seconds. Screen-capture preflight is
false on this host, confirming why screenshot comparison remains unavailable.
