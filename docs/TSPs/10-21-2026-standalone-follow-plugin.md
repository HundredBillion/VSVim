# Standalone Follow Plugin Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Extract Follow into a standalone multi-harness Neovim plugin and provide a separately installable, compatible Codex helper.

**Architecture:** The shared Lua engine accepts normalized events over a local pipe and never loads harness code. A terminal launcher owns its dedicated server, client, observer and private session descriptor. VSVim supplies project selection and its existing controls through a compatibility shim.

**Tech Stack:** Neovim 0.11+, Lua/libuv, Node 22.4+, pinned ws 8.22.0, Codex 0.163.0 App Server patch, Python standard library for runtime packaging, GitHub release artifacts.

## Global Constraints

- Preserve real received updates; no animation, delayed character revelation, or synthetic agent attribution.
- Initial runtime target: aarch64-apple-darwin; installed Codex must be explicitly compatible.
- Installed Codex, credentials, model choice, trust prompts, and approval configuration are preserved.
- Harness helpers are optional; ordinary Follow requires neither Node nor Codex.
- VSVim controls, SVGTree, icons, native protocol and layout remain compatible.
- No binary assets in Git, no developer-specific paths in the package, no global npm paths.
- No publishing or pushing is required to validate the local package.
- Implement inline under the approved scope; no additional design approval is needed for routine details.

## Resolved design checks

The source supports Unix WebSockets, and the copied runtime initializes after relocation.
The server requires the matching sibling Code Mode host. Internal title sessions must
be excluded by thread source and canonical root, not session count. Capture each
file's immutable baseline on its first progress notification; notifications precede
the public completed file item. Release the baseline on item completion, so a second
operation on that file reads its new saved revision. If first attachment occurs
after disk application and reconstruction is ambiguous, decline the preview.

Limit snapshots to 1 MiB, wire frames to 8 MiB, retained current operation snapshots
to 16 MiB, and socket write queues to 8 MiB. Session descriptors and sockets are
user-owned, under private directories. Ignore expired descriptors and foreign
protocols. Off detaches only the viewer, never kills an agent. Root switches advance
a connection generation; callbacks from the previous generation cannot render.

### Task 1: Extract the shared engine and retain VSVim compatibility

**Blocked by:** None

**Files:**
- Create in `/Users/davidlee/Projects/follow.nvim`: `lua/follow/init.lua`, `lua/follow/worker.lua`, `lua/follow/health.lua`, `tests/core.lua`, `README.md`, `CONTEXT.md`, `.gitignore`.
- Modify VSVim: `lua/vsvim/follow.lua`, `lua/vsvim/init.lua`, Follow tests' runtimepath setup.

**Interfaces:**
- Consumes: `setup({root=function():string?, before_open=function(buf), commands=false?})`.
- Produces: `status()`, `set_enabled(bool)`, `toggle()`, `preview({path,text,cursor})`, `finish_preview()`, `set_root(path?)`, `remember_root(path)`, `native_snapshot()`, `statusline()`, `lualine()`.
- Compatibility shim keeps the old command/click/key names and delegates to the one engine.

- [x] Run a standalone test before extraction and observe missing `follow` module.
  ```sh
  nvim --headless -u NONE -l tests/core.lua
  ```
  The test prepends only this repository, enables a temporary root, previews
  text, checks read-only content, turns Off, and asserts later text cannot render.
- [x] Move the tested engine and worker; replace SVGTree/markdown lookups with injected callbacks.
  ```lua
  require('follow').setup({root=function() return vim.fn.getcwd() end})
  assert(require('follow').preview({path=path,text='received',cursor={1,3}}))
  ```
- [x] Preserve VSVim aliases and test them against the plugin through `VSVIM_FOLLOW_SOURCE`.
  ```sh
  VSVIM_FOLLOW_SOURCE=/Users/davidlee/Projects/follow.nvim nvim --headless -u NONE -l tests/follow_stream.lua
  ```
- [x] Run existing saved-file and native tests; commit the extraction in each repository.

### Task 2: Add the shared local session protocol

**Blocked by:** 1

**Files:** `lua/follow/sessions.lua`, `tests/sessions.lua`, `doc/follow.txt`, `tests/source.mjs`.

**Interfaces:**
- Consumes descriptors `{protocol=1,id,harness,root,pid,socket,capabilities={live=true}}`.
- Consumes JSONL messages `{type='snapshot',session,operation,path,text,cursor}` and `{type='complete',session,operation,path}`, `{type='status',reason}`, `{type='hello',...descriptor}`.
- Produces `sessions.start(root, handlers)`, `sessions.stop()`, `sessions.select(id)`; callbacks `snapshot`, `complete`, `status`.

- [x] Reproduce failure with a non-Codex Node source publishing a real private Unix socket; Lua enables Follow before and after publication and reads snapshot messages.
  ```sh
  nvim --headless -u NONE -l tests/sessions.lua
  ```
- [x] Implement private descriptor discovery, live PID check, root match, generation-guarded framing, explicit multi-session selection, and bounded queues.
- [x] Verify Off/On reconnect, root changes, stale descriptors, mismatched session IDs, disconnect release, and a snapshot source with no Codex installation.
- [x] Add public source documentation and commit.

### Task 3: Package and install the optional compatible runtime

**Blocked by:** 1

**Files:** `bin/follow-codex`, `js/runtime.mjs`, `runtime/codex.json`, `patches/codex/*.patch`, `scripts/package-runtime.py`, `scripts/build-codex.sh`, `tests/runtime.test.mjs`, `.github/workflows/runtime.yml`, `lua/follow/install.lua`.

**Interfaces:**
- `runtime.resolve({dataDir,client,platform,arch})` returns validated runtime paths or an actionable error.
- `runtime.install({archive,sha256,dataDir,target})` verifies a pinned archive, stages the files, validates manifests and hashes, then atomically promotes the selected version.
- `follow-codex install --archive PATH --sha256 HASH` supports an independently built local release; plain install uses checked-in release metadata once published.
- `:FollowInstall codex` invokes the installer asynchronously and reports its launcher path.

- [x] Write a failing Node test for an unsupported client and corrupt archive.
  ```sh
  node --test tests/runtime.test.mjs
  ```
- [x] Implement platform/version/hash validation and protected archive extraction; package source/host/server notices and separate launcher scripts/dependency.
- [x] Package the existing built server and host through the actual packaging script, then install that archive into an isolated data directory.
  ```sh
  python3 scripts/package-runtime.py --help
  node --test tests/runtime.test.mjs
  ```
- [x] Verify interrupted installs preserve the selected version, binaries remain outside Git, and the installed launcher runs after the plugin directory is copied elsewhere. Commit.

### Task 4: Implement the Codex launcher and adapter

**Blocked by:** 2, 3

**Files:** `js/codex.mjs`, `js/progress.mjs`, `js/source.mjs`, `package.json`, `package-lock.json`, `tests/codex.test.mjs`, `tests/progress.test.mjs`.

**Interfaces:**
- `observe({endpoint,root,publish,signal})` discovers the terminal-created coding thread and subscribes without starting model requests.
- `createSource({root,harness,runtimeDir})` advertises a private descriptor and exposes `publish(event)` / `close()` with bounded current-operation snapshots.
- `follow-codex [--client PATH] [--] CODEX_ARGS` preserves terminal stdio and arguments; only the remote endpoint is supplied by the launcher.

- [x] Write a failing two-operation test: the second patch uses the first operation's saved output as baseline; title threads never select a coding session.
  ```sh
  node --test tests/codex.test.mjs tests/progress.test.mjs
  ```
- [x] Port exact-match patch reconstruction, native subscription, startup retries, and changed-text cursor calculation. Validate all paths and limits before reading or publishing.
- [x] Implement Unix transport, real terminal stdio, descriptor lifetime, signal forwarding, and graceful child cleanup; do not copy experiment trust/model/approval overrides.
- [x] Verify Add/Update, ambiguous-location fallback, unsupported changes, two turns, wrong-root events, bounded memory, and observer/model ownership. Commit.

### Task 5: Validate the installed workflow and complete documentation

**Blocked by:** 1, 2, 3, 4

**Files:** `tests/installed.test.mjs`, `tests/acceptance.py`, `README.md`, `doc/follow.txt`, `docs/execution/standalone-follow.md`; VSVim import pins and compatibility tests.

**Interfaces:**
- Public plugin import, supported install command, terminal launcher, source protocol, controls and health checks must match documentation.

- [x] Exercise a relocated plugin/runtime and a fake protocol server for deterministic CLI cleanup and argument-preservation checks.
  ```sh
  npm test
  nvim --headless -u NONE -l tests/core.lua
  nvim --headless -u NONE -l tests/sessions.lua
  ```
- [x] Run VSVim's stream, saved-file, regression and native RPC checks using the local plugin override.
- [x] Run an isolated real terminal coding session with ordinary approvals, then a second turn; verify session discovery, horizontal cursor advances, final content equality and cleanup.
- [x] Record actual results and limitations. Obtain an independent whole-change review and resolve substantive findings.
- [x] Commit the plugin, pin VSVim to that commit with a local override available, and retain build artifacts outside Git. Remote publishing remains a separate action.

## Completion evidence (2026-10-21)

Plugin commits: `833480b`, `8a9b298`, `650fc99`, `bdb9f9d`, `dfcc206`.
VSVim extraction: `72bb3ff`; the import now pins plugin `dfcc206` and retains
`VSVIM_FOLLOW_SOURCE` for local development. Until the remote is published, launch
this worktree with `VSVIM_FOLLOW_SOURCE=/Users/davidlee/Projects/follow.nvim`.

Fresh checks passed: 15 Node tests, standalone core and session suites, three
lifecycle regressions, VSVim saved-file/stream suites, seven regressions and three
native RPC tests. Installed real Codex acceptance exited 0: two operations, 243
displayed updates, 191 horizontal advances, final buffer equal to saved file,
Python exit 0 / six lines. Independent review findings resolved.

Local helper installed at `~/.local/share/follow/bin/follow-codex`; the compatible
client is checked explicitly. Local archive and sidecar are in plugin `dist/`,
ignored by Git. See plugin `docs/execution/standalone-follow.md` for hashes,
limitations and reproducible commands. No remote repository/release was published;
automatic download metadata intentionally remains empty. Other live harness
adapters remain future work, through the shared protocol.
