# Native code minimap

Status: approved by the user on 2026-10-19; implementation planning in progress.

Issue: https://github.com/HundredBillion/VSVim/issues/8

## Outcome

Give VSVim a built-in native minimap matching the approved HTML prototype:
actual tiny syntax-colored code, file-change bands directly over that code,
grey word-occurrence boxes, and a blue selected-row section. Users can see
file structure and navigate without leaving their editor selection.

The approved prototype is pinned at VSVim commit
`60db7a2dd2736ec1adbd71c92f68fb46fff91f6d` under
`docs/prototypes/minimap/`. Issue #8 embeds its complete HTML and screenshots.
It is a visual specification, not production code or an actual Git integration.

## Approved defaults

- Enable automatically for supported Sprite native editor grids. Provide
  `:VSVimMinimapToggle` and `vim.g.vsvim_minimap = false` to disable it.
- Show one minimap at the right edge of the native editor surface. It follows
  the focused ordinary file window. Focus in a sidebar retains the last valid
  file target; closing that target or having no file hides the minimap.
- Compare the current in-memory buffer against its file at Git `HEAD`.
  Saving does not clear changes; committing refreshes the baseline. Staging
  does not clear changes. This is a file-edit overview, separate from VSVim's
  merge-base review baseline in CONTEXT.md.
- Render lines at a small fixed readable scale, initially about 3 logical
  pixels per source line. Short files occupy only their natural height. Long
  files use a moving minimap window, as in VS Code, rather than shrinking
  every glyph toward zero. Map navigation still spans the entire file.
- Use a 160-logical-pixel strip when space permits. Hide it below an editor
  width of 480 logical pixels, releasing its space automatically.

The user approved these product defaults. The HTML specifies appearance and
interaction; this document additionally specifies long-file, Git, and split behavior.

## Appearance and selection

Preserve indentation, blank lines, syntax colors, and actual miniature text.
Paint translucent full-width blue added-line bands and yellow modified-line
bands behind the code. Their brighter horizontal starting edges remain visible
when another overlay overlaps them. Never move these markers into a separate
skinny column. A deletion has a thin yellow edge at its surviving boundary,
including beginning/end-of-file deletions.

A distinct translucent outlined viewport rectangle tracks visible source lines
in the target window. Selected rows use a blue translucent section; they do
not replace the viewport rectangle. Draw backgrounds, change fills, grey word
boxes, blue selected rows, bright change edges, code, and viewport outline in
that order. Keep code and all overlay types recognizable where they overlap.

Double-clicking a word retains Neovim's selection behavior and highlights exact,
case-sensitive occurrences throughout that buffer, including comments and
strings. Use the target buffer's Neovim word boundaries (`iskeyword`), not LSP
references or the user's search case settings. Highlight matching text in the
main editor and place one grey minimap box on every matching source row.
Selecting a new word replaces the matches. Escape, clearing selection, switching
files, or selecting a multirow range clears stale word highlights.

Characterwise, linewise, and blockwise Visual/Select selections mark all source
rows they actually touch. Respect an exclusive endpoint at the start of a row.
The minimap section covers the selected rows' full width even for blockwise
selection. Selection changes update this section while dragging offscreen.

## Navigation

Click miniature code to center the corresponding source line in the editor.
Click a change band to navigate to that hunk's first surviving line. Dragging
the viewport scrolls the target editor continuously; wheel input over the
minimap scrolls that editor. Hover reports the source line and any change or
word occurrence there. Minimap navigation preserves the selection and its
anchor; it must not replace the user's selected text or edit the buffer.

For long files, map pointer position through both the current minimap window
and a full-file drag track. The viewport's travel must reach the first and last
source lines without discontinuities or an unreachable tail. A click uses the
source line actually displayed under the pointer; dragging the viewport can
move the minimap window through the rest of the file.

### Preserved selection during minimap browsing

Approved during design hardening on 2026-10-19. Neovim cannot keep a Visual
selection endpoint far outside the viewport: a runtime probe of winrestview()
with an unchanged Visual cursor snapped topline back to that cursor. VSVim
therefore captures the selection before minimap navigation, temporarily leaves
Visual/Select mode, and draws the preserved selection while scrolling freely.
Word occurrences and minimap selected rows remain active.

Before the next keyboard input, restore the saved selection and original mode,
then deliver that input unchanged. Vim y/d/c and Cmd-C/X/V consequently act on
the original selection. Escape clears the preserved selection; a new editor
click clears it and follows normal mouse behavior. A file switch, target-window
closure, or buffer edit invalidates the preserved selection. Buffer edits from
another agent clear it rather than applying old positions to new text. Minimap
wheel and drag remain browsing operations. Preserve the original anchor and
endpoint orientation, register type, and Select versus Visual mode.

## Component boundaries

### VSVim: editor meaning

A built-in module owns the setting and active-file policy, source buffer data,
resolved syntax colors, viewport source-line range, selection rows, literal
word matches, and Git changes. It supplies a small snapshot/update interface to
the existing sprite.nvim bridge and receives line-navigation actions.

Use existing Neovim highlighting/parsing facilities; do not write another
language tokenizer. Resolve available Tree-sitter captures with a syntax
highlight fallback and ordinary foreground for unhighlighted text. LSP symbol
references and diagnostic markers are outside this feature.

Git work runs asynchronously. Resolve the repository and HEAD file using Git
arguments, never shell-interpolated filenames. Compare that text to unsaved
buffer contents using Neovim's diff facilities. Untracked files in a Git
repository count as added; non-Git files still have a working minimap without
Git bands. Removed HEAD files being edited use their existing HEAD baseline.
Refresh on buffer changes, writes, focus/return to editor, and relevant Git
metadata changes. Failed Git reads clear obsolete change bands rather than
pretending there are no changes or leaving another file's bands visible.

### sprite.nvim: transport and compatibility

Extend the existing native-grid capability negotiation with `grid-minimap-v1`.
Only enable the bridge when the host supports it and VSVim registers a provider.
Older Sprite and ordinary terminals keep their current editor behavior and
receive no unsupported minimap operations.

Coalesce editor notifications and transfer source text/color spans separately
from lightweight viewport/selection updates. Buffer identity, target-window
identity, content generation, and increasing message revision prevent delayed
results or pointer actions from affecting a new file. Request only one pending
snapshot per session, then service the latest invalidation.

The implementation spec must define exact wire fields, bounds, chunking,
revision rules, cancellation, and fixtures shared with the host before either
side is implemented. Reuse the existing Surface channel, not another socket.

### Sprite: native pixels and pointer geometry

Extend the optional grid presentation alongside native tabs. Reserve the strip
outside the Neovim grid, below native tabs; resize Neovim columns accordingly.
Use the same geometry for painting, pointer hit testing, wheel routing, cursor,
and IME positioning. Minimap events do not leak through as editor clicks.

Paint native miniature glyphs with GPUI using existing font facilities and
bounded caches. No embedded web view or copied VS Code/Zed rendering subsystem.
The host owns pixel-to-source-line mapping and sends typed navigation events;
Neovim owns focus, cursor, scrolling, and selections. Validate all incoming
ranges, colors, lengths, counts, and revisions atomically under existing Surface
message limits. Unsupported or invalid minimap state must not corrupt the grid.

## Responsiveness and lifecycle

Cache source/color data by buffer generation and theme. Viewport movement must
not rescan, recolor, or resend the entire file. Update edited regions and cancel
outdated asynchronous Git/highlight work on file switches. Bound per-message
work and build larger snapshots in scheduled chunks; avoid synchronous Git or
whole-file processing on every cursor event.

Draw only the source rows represented in the minimap window. Clip very long
lines to the strip width and retain original line numbers. Expand tabs by the
buffer's display rules and handle Unicode without splitting encoded characters.
Wrap and folds map back to original buffer rows: the minimap shows source lines,
not duplicated wrap rows; folded contents remain represented.

Clear or replace overlays on selection/mode changes, buffer disposal, theme
changes, disable, and adapter teardown. Turning the feature off releases its
width and pending work. Re-enabling builds current state. No plugin installation
step is exposed to the user.

## Verification and acceptance

1. Neovim integration checks use real buffers and mouse/Visual selections:
   offscreen syntax colors and matches, word boundaries, all selection types,
   exclusive endpoints, edits/undo, file switches, and selection-preserving
   navigation. Default Vim commands and Cmd shortcuts remain usable.
2. Git fixtures cover unsaved changes against HEAD, save/stage/commit, added,
   modified and deleted hunks, untracked/non-Git files, Unicode paths, and stale
   async results. No check can silently substitute simulated change groups.
3. Bridge/host shared fixtures cover feature negotiation, missing provider,
   chunked updates, bounds, stale generations, disable, and older-host fallback.
4. Native host checks cover width reservation, tiny/narrow panes, tabs and IME
   offsets, full-file navigation, dragging, wheel routing, overlay layering,
   scale/theme changes, and isolation from terminal/list/element surfaces.
5. Measure initial load, edit updates, and scrolling for 1,000-, 10,000-, and
   100,000-line files. Record latency, payload sizes, and memory before claiming
   responsiveness. Establish numerical budgets in the implementation spec using
   the current native-grid baseline.
6. Capture actual native screenshots of the approved code/change appearance,
   word boxes, and selected rows. Verify click/drag/wheel and buffer editing in a
   live Sprite test window. HTML screenshots do not prove native acceptance.

## Delivery

Use coordinated feature branches in VSVim, sprite.nvim, and Sprite. Implement and
verify the shared protocol and host, bridge, and provider before updating
VSVim's pinned adapter revision. Keep prototype artifacts available from issue
#8. Build a test Sprite application without replacing a running user's editor.
Document which host/adapter revisions were tested and whether a new Sprite
process is required. Publishing or installation follows the user's instructions.

## Source anchors inspected

- VSVim: `lua/vsvim/init.lua` plugin pins and setup;
  `lua/vsvim/tabs.lua` native provider; `CONTEXT.md` review terminology.
- sprite.nvim: `lua/sprite/adapter.lua` feature negotiation and coalesced tab
  requests; `lua/sprite/tabs.lua` provider and revision-checked action dispatch.
- Sprite: `crates/sprite-app/src/surface/grid.rs` grid operations/state;
  `surface/wire.rs` advertised features; `terminal_view/surfaces.rs` native
  geometry; `grid_paint.rs` text drawing and shape caches.
