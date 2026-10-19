# Input bridge freeze regression

Typing a continuation character could freeze the native editor. A native `v`, then
`r`, then replacement character reproduces the failure without any minimap provider.
The host window remains responsive, but the embedded editor is waiting for input.

The adapter wrapped every key in deferred `nvim_exec_lua`. While Neovim waits for
`r`/`f` continuations, deferred Lua cannot execute the `nvim_input` needed to finish
the command. The replacement hook now owns no input. The adapter queues the hook
before a mode request and delivers the original native API once when the hook
acknowledges or Neovim reports a blocking input wait. Earlier hooks must retire
before newer minimap/tab actions can preserve another selection. A mode reply is
not an acknowledgment that a preceding key was consumed. Fast input retains native
priority over deferred actions while blocked; paste retains its native deferred API.

This preserves mapping resolution after browsing: restoring Visual mode must happen
before choosing the Visual Cmd-C mapping. Splitting two independent notifications or
moving restoration into `vim.on_key` copied the browsed line in exploratory probes.

## Evidence

- Fixed adapter: `84c73cad6bedee1ebf2bd466a5382947ff611481`.
- Original adapter: `bb309536778274f9e2d9519f6a25d9e8f28baecf`.
- Host unchanged: `723766c9ef17cfb9dea10d681be03d134a1b2585`.
- Runtime: Neovim `v0.13.0-dev-761+g0639f6e41a` on macOS.
- `before.log`: run the final real-adapter regression with original production
  adapter/minimap files in an isolated copy; exit 1, replacement character never
  reaches the waiting editor. No escape/recovery key makes the assertion pass.
- `adapter.log`: 20,729 checks, zero failures, including original-selection Cmd-C,
  Cmd-X, Cmd-V, native paste, mouse, sidebar focus, resize/focus and source bursts.
- `selection.log`: 21 selection tests pass.
- `integration.log`: 5 complete isolated-profile setup tests pass.
- `native.json`: separate real AppKit keyboard events `v`, `r`, `x` changed exactly
  one character; native minimap browsing then Cmd-C copied the original `word`.
  Native clipboard assertions used a temporary in-memory provider and restored it.
- `review.md`: independent final review, no blocking findings.
- `ci.json` and `ci-summary.log`: all seven adapter CI jobs pass at `84c73ca`,
  including the pinned real provider on Linux/macOS with v0.11.0, stable and nightly.
  [CI run](https://github.com/HundredBillion/sprite.nvim/actions/runs/39253538050).

## Test design

Applied the six review concepts from the supplied *The Maintainer's Lens*:

1. New tests wait for mode, RPC replies, input-reader notifications and exact buffer
   outcomes. Generous watchdogs bound failures; elapsed time never indicates success.
   The production bridge uses no polling timer or retry timeout.
2. `tests/adapter_session.lua` extracts the existing native-minimap launch fixture;
   the new regression reuses its actual fake host, adapter, embedded editor and RPC.
3. Behavioral cases cover fragmented Visual/Normal replace, find, operator pending,
   mapping prefixes, multi-character `getcharstr`, Escape, bursts, paste and hook
   failure. RPC permutation tests cover stale replies, action barriers and teardown.
4. Reverting production files makes the new regression fail. The old suite had only
   whole-command bursts and mocked hook/API order, missing a real modal continuation.
5. Native commands run against both negotiated minimap and original direct input.
   The modal action/command ordering has an explicit direct-native baseline. Completed
   browse followed by Cmd-C retains the real VSVim selection and mapping tests.
6. CI checks out the real VSVim provider at an immutable revision on all six adapter
   OS/runtime combinations. Explicit invalid `VSVIM_SOURCE` fails instead of skipping.
   The obsolete combined hook/input function is removed, and provider contracts are
   documented in the adapter README. Stylua and `git diff --check` pass.

The mode request boundary is grounded in Neovim's special `ch_before_blocking_events`
queue, checked in official [v0.11.4 channel.c](https://github.com/neovim/neovim/blob/v0.11.4/src/nvim/msgpack_rpc/channel.c#L330-L337)
and [input.c](https://github.com/neovim/neovim/blob/v0.11.4/src/nvim/os/input.c#L503-L518),
and current upstream. The fix uses public APIs, not experimental fast Lua execution.

Run `nvim -l tests/run.lua` in the adapter checkout with `VSVIM_SOURCE` pointing to
this distro. Run the two Python suites with `uv run --with pynvim python tests/...`.
For native verification, launch the isolated preview using the existing native
control helper, then run `uv run --with pynvim python reproduce-native.py <meta.json>`.
The native check temporarily changes the private preview buffer and restores its
content, modified state, clipboard provider and focus afterward.

Previous performance evidence is unchanged; this input fix does not claim a new
performance measurement. No host changes, merges, or application installation.
