# Familiar editing controls

Branch: `feat/familiar-editing`.

The requested Cmd shortcuts add familiar editing actions while leaving native
Vim commands and registers available. `editing.save(buffer, on_saved)` owns the
save flow shared by Cmd-S and tab closing. Unnamed files ask for a path; a
canceled prompt or failed write leaves the buffer open and modified.

Neovim's `confirm` option provides the quit prompt for `:q` and `:qa`. `hidden`
allows switching files without saving. Recovery uses native swap files with a
one-second idle update interval; persistent undo retains saved history across
restarts. There is no new session database or silent source-file autosave.
Explicit discard and `:qa!` retain their normal meaning. This is crash recovery,
not a Keep for next time exit option or automatic workspace restoration.

## Compatibility evidence

| Field | Evidence |
| --- | --- |
| Decision | Native confirmation, swap recovery, persistent undo; Cmd mappings use the `+` clipboard register and `nvim_paste` for selection-aware paste. |
| Version chain | `README.md` and `init.lua` require Neovim 0.13 nightly. Verification used `0.13.0-dev-761+g0639f6e41a` from `/Users/davidlee/.local/nvim-nightly/bin/nvim`. |
| Primary sources | [confirm, hidden, swap and undo options](https://neovim.io/doc/user/options/), [nvim_paste](https://neovim.io/doc/user/api/#nvim_paste()), [clipboard providers](https://neovim.io/doc/user/provider/#clipboard), [recovery](https://neovim.io/doc/user/recover/). Installed runtime help and actual RPC/UI behavior were checked. |
| Local precedent | Existing tab close used `vim.ui.select` but wrote unnamed buffers directly. It now uses the shared save flow. Native Sprite paste already uses `nvim_paste` through its adapter. |
| Verification | `tests/editing_rpc.py`: actual key input and UI prompt choices, isolated clipboard provider, named and unnamed saves, canceled and failed writes, native Vim keys retained, persistent undo and recovery after killing an editor. Existing distribution integration tests also run. |

## Limits and host dependency

Neovim's native quit confirmation saves an unnamed buffer as `Untitled` after
Yes. Cmd-S or tab Save and close asks for a filename first. Keeping native quit
commands preserves their existing command grammar and force semantics.

Sprite's native Surface handler consumed Cmd-C without forwarding an event.
The companion `fix/native-editor-copy` branch in Sprite forwards Copy to the
focused Surface while retaining its existing Paste routing. Its GPUI regression
test dispatches the actual shortcut and asserts exactly one input event reaches
the native editor. The distro includes that companion source patch under
`extras/sprite-native-copy.patch`; applying it requires rebuilding/updating the
Sprite host. A running, older Sprite process will keep its old input handler.
Ordinary terminals also need to forward Cmd shortcuts to Neovim.

The local `nvim-nightly` executable is a wrapper around an installed VSVim
release. All verification commands set `VSVIM_NVIM` to the underlying Neovim
binary so they exercise this checkout.

## Verification commands

```sh
VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim \
  uv run --with pynvim python tests/editing_rpc.py
VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim \
  python3 -m unittest discover -s tests -p '*_test.py'
```

In Sprite:

```sh
cargo fmt --all --check
cargo test -p sprite-app --lib terminal_view::surfaces::tests
```
