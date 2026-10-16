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

## SCM integration (milestone 1b)

Bundled scm.nvim f2ba987bdd921a6563174bf4051a823ceadf601d, published on
HundredBillion/scm.nvim feat/standalone-sidebar (draft PR #1). Opts select the
Snacks-free auto renderer. Space-g-s / Ctrl-Shift-g open source control;
Space-e / Ctrl-b hand off to SVGTree. Terminal tabline identifies SOURCE CONTROL.

The new clean-install integration check lists real Git changes, checks mutual
exclusion with SVGTree and no Snacks loading, and preserves the captured repo
root when cwd changes before returning to explorer. Required command/API checks
include SCM. The installed local VSVim profile has been synced to the pin.

SCM's separate five-script suite passed. A live Sprite dock acknowledged nine
repository/file rows without error. Independent integration review found no
Important issues; the subsequent cwd-change regression failed before its fix
and passed after. Linux runtime and screenshot comparison remain unverified.
Full live PR diffs, deleted-file history, instant filesystem watching, CRP and
agent following remain later milestones; current refresh triggers are writes,
focus return, terminal exit and r.

## Native sidebar shortcut correction

The native SVGTree dock did not receive Neovim mappings. Added callback mappings
for Space-g-s / Ctrl-Shift-g and pinned SVGTree d33176b24600dd36521fe1137ff8e40e84b40f71
(draft svgtree.nvim PR #24). SVGTree accepts callbacks during normal and pending
structure updates and normalizes Space key events consistently. No SCM behavior
change was needed.

Regression tests first reproduced missing native handoff, then passed with the
patched pin: the fresh-install suite exercises Explorer -> SCM -> Explorer -> SCM
through both real plugin controllers with a fake Sprite transport. Four VSVim
tests pass (13.646s); the complete SVGTree suite passes. Independent review's
Space normalization and pin findings are addressed. Linux remains unverified.

## Bidirectional sidebar focus

Added normal-mode Ctrl-h/l navigation: move to a neighboring Neovim window first,
then focus a native dock on that side at the editor edge. SVGTree already exposes
native focus; SCM now exposes focus(side) and handles Ctrl-l even during a pending
row update. Explicit editor focus prevents the initial row acknowledgement from
stealing focus back. Pinned SCM 8aeb27e3e9b5edd824c0abe31e55f328c06ea5ef.

Regressions reproduced missing Ctrl-h routing and missing SCM Ctrl-l handling.
All five SCM test scripts pass. Four VSVim clean-install tests pass (16.871s),
including native and terminal roundtrips for both plugins and editor split
navigation. Independent review found no Important issues. Live Sprite focus
requests are also exercised after hot-loading the updated mappings/plugin.

## JB Theme default

User selected the installed `kenethriera.jb-theme` and confirmed matching VS Code's
Menlo font. Active variant: JetBrains Dark Theme, extension 1.0.35, CC0-1.0.
Added `vsvim-jb-dark`, source notes, and a Menlo 12 Sprite profile. The previous
colorscheme remains available. Native palette overrides are opt-in for both
plugins, pinned to SVGTree 6ae2a488b9fc22901b0042340c86aaf9da2d3094 and SCM
ca4c8148e2eceb366ff7695d23bf98d303b4acb8.

Four VSVim tests pass (13.792s), including native background and syntax palette
checks. Both plugins' targeted native view tests pass; independent palette review
found no material errors. Sprite parsed the bundled config without complaints.
Created the previously absent ~/.config/sprite/config.toml from that profile and
reloaded it in the live window. Runtime inspection confirms Menlo 12, editor
#1e1f22, native sidebar #2b2d30 and the new colorscheme. Physical screenshot
comparison remains unavailable; TextMate-to-Neovim scope mapping is approximate.
