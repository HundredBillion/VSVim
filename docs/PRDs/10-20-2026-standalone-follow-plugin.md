# Standalone Follow plugin and optional Codex runtime

Status: approved 2026-10-21, including the harness-independent core and small
adapter contract. The smaller-helper distribution uses installed Codex checks.

## Outcome

Publish Follow as a standalone Neovim plugin, provisionally
`HundredBillion/follow.nvim`. VSVim imports a pinned plugin revision and supplies
its explorer root and existing controls. The product goal is to support coding
harnesses generally, including Codex, Claude Code, OpenCode, Pi, and Hermes.
Codex is the first implementation and packaging target, not the plugin's
identity or a dependency of its shared Follow behavior. Users can follow real
incoming Codex edits in VSVim without rebuilding Codex, changing their installed
Codex, or giving the plugin model credentials.

The normal workflow becomes:

1. Install the plugin through VSVim's plugin manager.
2. Once, install the optional compatible Codex helper with `:FollowInstall codex`.
3. In the agent pane, run the installed `follow-codex` launcher from the project.
4. Open VSVim in the adjacent pane and enable Follow with Space-a-f or its icon.

Command names are proposed public interfaces, not currently installed commands.
The installer reports the absolute launcher path. Users may add its directory
to PATH; installation does not edit shell startup files or shadow `codex`.

Either editor or agent may start first. An already-running Codex session started
without the launcher remains eligible only for saved-file Follow. Live Follow
does not retrofit the patched server into that process.

## Distribution choice

Use one plugin repository with optional, versioned runtime release assets.
The user selected a smaller helper with installed-Codex compatibility checks.

| Approach | Consequence | Decision |
| --- | --- | --- |
| Keep all code in VSVim | Couples agent integration and runtime updates to editor releases | Declined |
| Standalone plugin plus optional server/host helper | Small plugin checkout; installed Codex must match a tested runtime | Selected |
| Bundle a private Codex client as well | Stable client/server pairing, larger download and duplicate client | Deferred |

The initial supported target is Apple Silicon macOS, matching the successful
experiment. Other targets require their own build, packaged dependency checks,
and terminal acceptance run before being advertised as supported.

## Ownership

The plugin owns Follow state, saved-file watching, preview navigation and
conflict handling, session discovery, and its Codex stream receiver. Extract
the existing tested behavior; do not maintain a second implementation in VSVim.
It can run in ordinary Neovim without Sprite or SVGTree.

VSVim supplies a root callback backed by SVGTree, keeps Space-a-f and its
existing commands, and renders the existing statusline/native control. Its
`vsvim.follow` module becomes a compatibility shim over the plugin so current
Sprite adapter calls continue to work. Standalone users get plugin commands
and an optional lualine component/click callback; lualine is not a dependency.

The launcher owns the temporary patched App Server, the installed terminal
Codex client connected to it, and the stream observer. Terminal input and model
requests remain owned by Codex. The observer does not start turns, replace the
selected model, lower approval settings, bypass folder trust, or override agent
instructions. Prototype-only experiment overrides must be removed.

The shared core owns session selection, project boundaries, display, user
takeover, and Off/On behavior. Harness-specific code owns event subscription,
authentication through that harness, partial-edit interpretation, and any
necessary launch integration. Neither the shared core nor VSVim imports Codex
protocol types or assumes a Codex process, tool name, model, or configuration.

Use a small adapter contract for session identity, canonical workspace roots,
capabilities, snapshot updates, completion, and disconnect/error events.
Updates identify their session, operation, file, text, and cursor position;
operation identities are opaque to the shared core. Each adapter reconstructs
its own harness's partial edits before sending snapshots. Codex thread/turn/
item IDs remain inside its adapter. Adding another harness must not require
changing VSVim's controls or copying the preview/navigation engine.

The first live adapter is Codex. Subsequent adapters target Claude Code,
OpenCode, Pi, and Hermes after inspecting each available event interface.
Use ACP where it exposes the required edit stream; otherwise use the harness's
native supported interface or a separately packaged integration. Do not require
every harness to implement ACP or use the Codex launcher/runtime. Install each
harness helper independently; using another adapter must not download Codex.

Report capabilities honestly: live edits when partial edit events are
available, saved-file navigation when only disk changes can be observed, and
an explicit unavailable reason when neither integration is usable. Saved-file
observation does not identify the responsible agent. The goal of broad harness
support does not justify claiming live typing from a source that exposes only
completed edits. No simulated typing is allowed. Build only the small adapter
boundary and the Codex implementation initially, not a speculative framework
or placeholder implementations for the other harnesses.

## Runtime assets and compatibility

Keep binaries out of the Git repository. Ship platform-specific archives with:

- The patched `codex-app-server`.
- Its matching `codex-code-mode-host`, which this App Server resolves beside
  its executable; do not retain a symlink into the user's global npm package.
- A manifest identifying upstream commit/version, Follow patch revision,
  platform, compatible client versions, file hashes, and preview capabilities.
- Applicable licenses, upstream NOTICE, and modification notices.

Keep the upstream source revision and small patch series reproducible in the
repository. Release automation builds them and runs parser/protocol tests.
Initial compatibility is limited to the verified Codex 0.163.0 pairing; do not
assume newer or older clients work. The launcher checks the actual selected
client before starting, and an unsupported version gives an actionable error.
An explicit client path can select an already-installed compatible client.

Checksums and manifest contents must identify the patched build: its current
`--version` output alone is identical to upstream. A runtime install is staged,
validated against the pinned release hashes, and atomically promoted. Keep the
previous working version until replacement succeeds. Running sessions retain
their selected runtime. Plugin upgrades do not silently replace an active agent.

Store the optional runtime and launcher in a user data directory outside the
plugin checkout, respecting XDG_DATA_HOME with a documented default. Store
session descriptors and sockets under a user-owned runtime directory. No Rust
toolchain is needed by users installing prebuilt assets.

Node is an explicit launcher prerequisite for the first release. Retain the
small JavaScript observer rather than rewriting proven behavior in another
language. Package one pinned pure-JavaScript WebSocket dependency (`ws`) with
the launcher; users need no npm build step or native addon. A plugin install
alone does not download Codex binaries or start a background service.

## Discovery, transport, and lifecycle

The launcher starts one dedicated server for its invocation. Prefer the tested
Codex Unix-socket transport for local client connections, with user-only socket
and directory access. That transport still carries WebSocket frames; it is not
raw newline JSON. The observer uses `ws` IPC support. The plugin's connection
to the launcher uses bounded newline JSON over a separate local pipe, supported
by Neovim's existing libuv facilities. No extra headless Neovim process is needed.

A descriptor records launcher identity, canonical project root, transport
version, endpoint, and selected thread ID. Validate descriptors and liveness
before use. Match the active explorer project and exclude internal title
threads. If multiple coding sessions match, offer a session choice rather than
following whichever session last wrote a file. Root changes invalidate the
previous attachment. Do not inspect terminal text or identify agents by timing.

Off stops display/navigation, without canceling the agent. Re-enabling uses a
current snapshot and new updates, with no replay animation. Keep at most the
latest eligible snapshot per file for the active patch, with bounded total
memory; disconnect a stalled consumer rather than building an unlimited queue.
No timed character revelation or artificial pacing is permitted.

Before rendering an update patch, capture the correct saved baseline for that
patch item. Never repeatedly apply cumulative progress diffs to the previous
preview. Scope state by thread, turn, item, and canonical file path. Ambiguous
patch locations fall back to the final saved file with a visible reason. The
first release supports Add File and Update File on supported text; unsupported
renames, deletions, and line-ending cases retain safe saved-file behavior.

On completion, reconcile the final saved file through the existing validation
and unsaved-conflict checks. On error/disconnect, release preview suppression
and report the reason. Closing VSVim detaches its viewer; it must not kill an
agent in another pane. Closing the Codex client cleans up its launcher-owned
observer, server, descriptors, and sockets. Stale descriptors are ignored.

## Acceptance checks

- Existing Follow behavior and native/statusline controls pass after extraction.
- Shared Follow code and VSVim integration contain no Codex protocol or runtime
  dependency. A second test source can drive the same controls, project checks,
  and preview lifecycle without installing or launching Codex.
- Adapter capability reporting distinguishes real live updates from saved-file
  navigation. Unsupported live sources never silently simulate typing.
- No SVGTree content, native icons, or buffer-tab layout changes.
- Clean installation from a local package works without any `/tmp` or developer
  absolute paths and without accessing global npm package internals.
- Runtime/client incompatibility, wrong hashes, unsupported platform, and
  interrupted installs fail before launching an agent; existing installs survive.
- Agent-first and editor-first launch discover the same intended session.
- Multiple projects and internal title threads cannot redirect the viewer.
- Two successive turns use separate patch baselines and reconcile final files.
- Off/On, manual takeover, unsaved conflicts, root changes, disconnects, and
  editor exit preserve user work and agent ownership.
- A real terminal run shows horizontal movement from actual received edits,
  with final preview/file equality and no animation. The session uses the user's
  selected model and ordinary approvals/configuration.

## Evidence and release limits

The accepted prototype already demonstrated real terminal streaming and control
integration; see `docs/execution/follow-terminal-session-experiment.md` and
`docs/execution/follow-stream-controls.md`.

A packaging probe copied the server and host into an independent directory,
included a version/hash manifest and notices, and produced an archive under
`/tmp/vsvim-follow-packaging`. Its current **unoptimized development build** is
410.1 MiB unpacked and 127.1 MiB compressed. An optimized release size has not
been measured. This probe is not a production release or full installer.

The archive was extracted into a separate directory, both executable hashes
were checked, and that extracted App Server successfully initialized and
answered `thread/loaded/list` over a Unix socket using `ws` 8.22.0. No model
turn was started. Evidence is in `/tmp/vsvim-follow-packaging/probe.json` and
`smoke-result.json`. This validates relocation and transport; the installer,
editor IPC, and terminal lifecycle still require implementation and testing.

The stream relies on experimental App Server notifications and a maintained
Codex patch. An independent plugin removes that maintenance from VSVim releases;
it does not remove the maintenance itself. Prefer upstream support once the
same acceptance checks pass without the patch.

Primary references:

- [lazy.nvim plugin spec](https://lazy.folke.io/spec): pinned/local plugin loading,
  setup options, and install hooks.
- [Codex App Server](https://learn.chatgpt.com/docs/app-server): remote terminal
  connections, shared initialization, and WebSocket-over-Unix transport.
- [ws IPC API](https://github.com/websockets/ws/blob/master/doc/ws.md#ipc-connections):
  client connections to Unix sockets without implementing WebSocket framing.
- Version-matched local Codex source: `rust-v0.163.0`, commit
  `83086188ae0614bd882818ff1aa23f3194962012`; `install-context/src/lib.rs` resolves
  the sibling host, and `.github/workflows/rust-release.yml` packages server/host
  together. The local runtime and CLI report 0.163.0; Node reports 26.12.0.
