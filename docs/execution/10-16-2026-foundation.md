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
