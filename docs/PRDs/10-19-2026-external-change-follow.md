# Follow external file changes

Status: approved and implemented on the feat/follow feature branches.

## Outcome

When Follow is enabled, VSVim opens files changed externally under the SVGTree
project root and positions the cursor at a changed region. This works with any
coding agent that writes to that filesystem, without agent-specific setup.
It also observes changes from formatters, Git, scripts, and other editors.
The UI must not claim to know which process or agent made a change.

This milestone implements filesystem following instead of the selected-agent
integration described in the original VSVim PRD. It does not require PR review,
a coding-session selector, or a reviewer conversation.

## Controls and visible behavior

Follow starts off for each editor session. `:VSVimFollowToggle` and normal-mode
`<leader>af` toggle it. `:VSVimFollowOn` and `:VSVimFollowOff` provide explicit
commands. The status bar always provides a clickable Follow control, including
on the welcome screen, with visibly distinct enabled and disabled states.

Use Zed's crosshair shape for the native Sprite control, with the required
upstream asset attribution. Its tooltip describes following external file
changes and shows the shortcut. Ordinary terminals and older hosts use a
clickable text/glyph control and the same commands. Keep VSVim's existing
statusline; installing lualine is unnecessary for this behavior.

Enabled Follow waits for new changes after its initial snapshot; it must not
open every existing or Git-modified file on activation. A completed external
write opens or refreshes the file in an ordinary editor window and scrolls the
chosen changed line into view. Select the last changed region in file order
when a single write changes multiple regions; the filesystem cannot reveal
the author's edit order. Use column one of the changed line. A new file opens
at its first line. A deletion has no navigable target and does not close the
developer's buffer. Markdown targets open in source so the changed line is visible.

Coalesce rapid writes to the same file and navigate to the latest available
contents. Across files, use the latest observed change, with deterministic
ordering for changes observed together. Never describe this ordering as the
agent's exact editing order. Do not steal keyboard focus from another Sprite
pane or a native sidebar. Turning Follow off stops further automatic jumps.

While enabled, deliberate editor navigation, selection, or editing turns
Follow off so the user can read and work. Follow's own navigation must not turn
it off. Re-enabling starts from the current filesystem snapshot and waits for
the next write. This milestone has two user states, on and off, rather than a
separate paused mode.

## Scope and file safety

Watch the entire current SVGTree root, including collapsed subdirectories,
rather than only the visible rows. Retain the last explorer root when the
sidebar is hidden or SCM replaces it. Use the editor working directory before
an explorer root is available. Changing the explorer root resets the snapshot
without treating the newly included files as new edits.

Ignore Git metadata, dependency/build/cache directories, editor temporary and
swap files, binary files, and Git-ignored files. Follow new untracked source
files. Do not traverse symlinks outside the root or follow directory cycles.
All operations remain within the selected root. Final technical limits and
exclude defaults must be documented in the implementation spec and README.

Suppress writes initiated by this VSVim instance by comparing saved content,
rather than suppressing every change within a time window. A subsequent
external change must still be observed. No process attribution is inferred.

Never replace a modified buffer, run a forced reload, save automatically, or
discard undo history to follow a change. If the target has unsaved changes,
leave its contents intact, disable Follow, and show a clear conflict notice.
Also defer navigation during command entry, prompts, insert mode, or active
selection; do not interrupt input or overwrite it. Discard stale pending work
when Follow is disabled or its root changes.

## Responsibilities and responsiveness

VSVim owns root selection, asynchronous filesystem observation and snapshots,
own-save suppression, changed-region selection, navigation, state, and commands.
Use Neovim's existing asynchronous facilities rather than a new daemon or
agent integration. Snapshot discovery and content comparison must not block
typing or painting on large projects. Bound file sizes, queued work, retained
content, and filesystem concurrency. Establish a baseline for previously
unopened files so changed-line detection does not depend on Git history.

sprite.nvim carries the native control's state and click action over the
existing editor connection. Sprite renders and hit-tests the exact crosshair
in the footer. Add a negotiated capability only if the existing footer cannot
represent the icon and action. Keep compatibility with ordinary terminals and
older hosts. No agent file-write telemetry is added in this milestone.

Watcher failures must leave editing usable and display a useful Follow status.
Shutdown, disabling, and root changes release watchers, timers, snapshots, and
pending work. Late callbacks must not reopen files after disabling Follow.

## Acceptance checks

1. Enable by command, shortcut, and status-bar click; all controls share state.
   Verify initial activation causes no file jumps and disabling stops navigation.
2. From a separate process, change an unopened nested file and verify its new
   contents, correct changed region, cursor, and viewport. Repeat for an open
   clean file, a new file, deletion-only edits, and multiple changed regions.
3. Verify atomic-save replacements, rapid writes, multiple files, rename,
   deletion, and a newly created directory are handled without errors or stale
   jumps. Untracked text files work without a Git repository.
4. Save inside VSVim and verify no Follow jump. Immediately change the same file
   externally and verify it is still followed.
5. Verify ignored/generated files, binary files, outside-root symlinks, and
   changes outside the explorer root cause no navigation. Hidden explorer and
   root changes follow the scope rules above.
6. Make unsaved edits and externally change that file. Verify all local text
   survives, Follow disables, and the conflict is reported. Verify ordinary
   navigation/selection/editing disables Follow without its own jumps doing so.
7. Verify prompts, insert mode, Markdown source, multiple windows, sidebar
   focus, native footer resizing, and older-host/terminal fallback.
8. Run a real coding agent editing the watched project. Verify updates arrive
   without agent configuration. Also verify a scripted external write follows
   identically, demonstrating the actual attribution limits.
9. Measure activation and write-to-visible-change latency on a large project;
   record memory/work limits, input responsiveness, and watcher cleanup. Target
   a visible update within one second of a settled write on the local fixture.

## Source anchors

- VSVim: `lua/vsvim/appearance.lua`, `lua/vsvim/sidebar.lua`,
  `lua/vsvim/init.lua`, `CONTEXT.md`, and the original VSVim PRD.
- SVGTree: `lua/svgtree/init.lua` (`root`, `open`, and root-change handling).
- sprite.nvim: `lua/sprite/adapter.lua` and `lua/sprite/input.lua`; the current
  connection carries rendering and input rather than identified agent edits.
- Sprite: `crates/sprite-app/src/surface/grid.rs` and
  `crates/sprite-app/src/terminal_view/surfaces.rs` for the existing footer.
- Zed: `crates/agent_ui/src/conversation_view/thread_view.rs` uses
  `IconName::Crosshair` for Follow; the asset is `assets/icons/crosshair.svg`.

## Delivery

Review this written design, then create the implementation spec with the exact
watching strategy, budgets, footer transport, and verification commands before
production changes. Update the domain model to distinguish filesystem Follow
from future following of an identified coding session. Deliver tested feature
branches and an actionable native preview without replacing the running editor.
