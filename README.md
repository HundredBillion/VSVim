# VSVim

An independent Neovim distribution for reading and reviewing agent-written code.

This development milestone provides isolated startup, a JetBrains Dark Theme
theme, file tabs, status line, the svgtree explorer, and a Snacks-free SCM sidebar.
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

Cmd-Z undoes, Cmd-C copies, Cmd-X cuts, Cmd-V pastes, Cmd-A selects the whole
file, and Cmd-S saves. These shortcuts also work while typing. Copy and cut use
the selected text, or the current line when nothing is selected. They use the
system clipboard, and pasting replaces selected text. Saving an unnamed file
asks for a filename. Ordinary Vim commands (`u`, `y`, `d`, `p`, `ggVG`, and `:w`)
remain available. Cmd shortcuts require a host that forwards those keys;
ordinary terminals may reserve some of them for their own actions.
Sprite's native editor panes also need the companion
[Cmd-C host fix](extras/sprite-native-copy.patch). Older hosts consume Cmd-C
before it reaches Neovim; rebuild/update Sprite with that patch and open a new
Sprite process to enable copying from native editor selections.

`:q` and `:qa` ask whether to save unsaved changes before an operation would
discard them. Choose Yes to save, No to discard, or Cancel to keep editing.
File-tab close controls offer Save and close, Discard changes, and Cancel.
Canceling a filename prompt or failing to save keeps the file open. Switching
files keeps unsaved edits in memory without prompting. `:qa!` still explicitly
discards unsaved edits and quits. Use Cmd-S to choose a name for a new document
before quitting: Neovim's native quit prompt otherwise saves unnamed documents
as `Untitled` when you answer Yes.

VSVim keeps Neovim's swap-based crash recovery enabled and updates recovery
files after one second of idle time. After a crash, reopen the affected file
and choose Recover when Neovim finds its recovery file. Saved undo history also
survives restarts, so `u` can undo older saved edits. Recovery and undo files use
VSVim's own state directory. This does not silently save edits to your source
files or restore edits you explicitly discarded when closing or quitting.

Use normal Neovim editing modes. Space is the leader. Press Space then e,
or Ctrl-b, to toggle the explorer. Space-g-s or Ctrl-Shift-g
opens source control (`:ScmToggle` also works). Space-g-s works in terminals
that cannot distinguish Ctrl-Shift-g. In SCM, Enter opens a file, h/l collapses
or expands a repository, r refreshes, Escape returns to editing, and q closes.
Space-e or Ctrl-b switches from SCM to SVGTree. These shortcuts also work while the native Sprite explorer is focused.
Ctrl-h and Ctrl-l move focus left and right between editor splits and either
sidebar, including native Sprite docks.

SCM uses a native Sprite dock when available and a normal split elsewhere.
It refreshes after editor writes, focus return, terminal exit, or r. Full live
PR diffs, deleted-file history and instant external-change watching await prism;
this milestone lists repository changes using SCM's default-branch baseline.

## Go to definition and languages

Command-left-click (macOS) or Super-left-click (Linux) on a function or method
opens its definition and places the cursor at column one of that line. `gd`
performs the same action at the cursor; `Ctrl-o` returns to the previous location.
With an updated Sprite host, holding Cmd/Super over a highlighted function or
method also changes the mouse pointer to a pointing hand. This requires the
native Sprite adapter; ordinary terminals retain their own mouse pointers.
Popup headings use Sprite’s bold system UI font, matching the Explorer.
Multiple distinct definitions open a compact floating chooser with method signatures
above muted filenames and line numbers. Five choices fit at once; use arrows or
`j`/`k` to browse, Enter or a click to open, and Esc to cancel. Ordinary terminals can use `gd`
even when they do not forward Command/Super mouse events.

VSVim includes pinned Mason, mason-lspconfig, and nvim-lspconfig plugins. The first
interactive launch installs these servers in VSVim's own data directory:

| Languages | Server |
| --- | --- |
| Lua / Neovim configuration | Lua Language Server |
| Python | Pyright |
| Ruby | Ruby LSP |
| Go | gopls |
| Rust | rust-analyzer |
| TypeScript, JavaScript (including TSX/JSX) | TypeScript language server |

Server downloads and first project indexing take time. Use `:Mason` to inspect
installation progress, `:VSVimInstallLsp` to retry installation, and
`:checkhealth vim.lsp` to inspect attached servers. Headless startup does not
install servers automatically; the install command also works for provisioning.
Server releases come from Mason's registry; plugin revisions are pinned, but
server releases are not frozen by the distro.

Language runtimes/toolchains still need to be available: Node/npm (the tested
TypeScript server requires Node 22.22.2 or newer), modern Ruby/Bundler, Go, and
Rust/Cargo with rust-src. Projects need their normal dependencies and configuration.
Ruby projects with a Gemfile need a Gemfile.lock (`bundle install`). Ruby LSP's
support bundle uses VSVim's data directory unless `BUNDLE_PATH` is set. On macOS,
VSVim uses an installed Homebrew Ruby when PATH otherwise selects Apple's old
`/usr/bin/ruby`; it preserves Ruby version managers already selected on PATH.

The real-server integration check is `VSVIM_TEST_LANGUAGE=python ./bin/vsvim
--headless '+lua dofile("tests/lsp_servers.lua")' '+qa!'` (repeat with lua, ruby, go,
rust, typescript, javascript). The mouse RPC check is
`uv run --with pynvim python tests/mouse_definition_rpc.py`; add `--real` to
exercise the installed Python server and mouse-release behavior together.

## Sprite

Inside an eligible Sprite pane, the launcher automatically starts the native
editor adapter using the same Neovim nightly binary. On first launch it installs
the adapter before opening the editor. Other terminals retain normal Neovim
rendering. Set `VSVIM_NATIVE=0` to force the terminal path. Headless, embedded,
script, help, and version invocations bypass the native adapter.

The palette follows the VS Code extension `kenethriera.jb-theme` (JetBrains Dark
Theme): charcoal editor, gray sidebars, orange keywords, green strings, and
blue functions. See [theme sources and font setup](docs/themes/jb-theme.md).
For the matching Menlo 12 font in Sprite, launch with
`sprite --config extras/sprite-jb.toml -e ./bin/vsvim` from this checkout.
Sprite builds advertising `grid-tabs-v1` show 35-pixel native file tabs with
SVGTree's SVG icons and the JB palette. Click a tab to select its buffer; click
its close control to close it. Modified files ask before closing. Scroll the
strip horizontally when tabs overflow; selecting a buffer keeps its tab visible.
Ordinary terminals and older Sprite versions keep the one-row tabline with
Menlo-compatible symbols, close controls, and overflow arrows. After upgrading
Sprite, open a new Sprite process to use the native strip; existing windows
keep running with their original host. The explorer opens by default; put
`vim.g.vsvim_auto_explorer = false` in `user.lua` to disable that behavior.
User overrides run after appearance setup, so a different colorscheme can be
selected there.

Sprite controls font metrics and native panel geometry. This is an initial
visual implementation, not a claim of pixel-identical VS Code rendering.

## Development checks

Run `uv run --with pynvim python tests/editing_rpc.py` to exercise the Cmd
shortcuts, quit choices, unnamed-file saves, failed-save preservation, saved
undo history, and recovery after killing an editor process. Clipboard checks
use an isolated provider and leave the desktop clipboard alone. Set
`VSVIM_NVIM` to the underlying Neovim executable if `nvim-nightly` is a wrapper.

Run `python3 -m unittest discover -s tests -p '*_test.py'` with Neovim nightly
and Git on PATH. Integration checks download pinned plugins into a temporary
profile, verify the explorer and user overrides, then check cached startup
without Git. They do not use your normal Neovim configuration.
Use `VSVIM_NVIM=/path/to/nvim` to select an actual nightly binary.
See [performance evidence and reproduction](docs/performance.md) for the
Explorer benchmark and plugin job-count checks.

Tested locally on macOS with Neovim `0.13.0-dev-761+g0639f6e41a`. Linux runtime
validation has not run. Native Sprite startup was exercised, but screenshot
comparison is still pending because macOS denied window capture.
Plugin revisions are fixed in the distribution; `:Lazy sync` preserves those
revisions. Updates to bundled versions ship as changes to VSVim's pins.

Lua support includes Neovim's annotated API library, so `gd` and Cmd/Super-click
on calls such as `vim.api.nvim_get_hl` resolve to their Lua API declarations.
LuaJIT is the default runtime; projects can override Lua settings in `.luarc.json`.
