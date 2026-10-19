# Markdown preview in one buffer

Status: product design and written PRD approved in conversation on 2026-10-19.
Implementation in progress on coordinated `feat/markdown-preview` branches.

## Outcome

Open Markdown files as rendered documents in VSVim. A toolbar button switches
between the preview and editable Markdown in the same editor pane. Both views
use the original Neovim buffer, with one file tab, one undo history, and the
existing save and close behavior.

The user approved a rendered preview backed by the same buffer, with VS Code's
source icon in preview and Zed's eye icon in source mode. They also approved
extending Sprite and sprite.nvim to support it.

## User behavior

- A newly opened Markdown file defaults to preview when the Sprite host
  supports this feature. Use Neovim's Markdown filetype detection, including
  files opened from the command line, Explorer, and existing file tabs.
- In preview, show VS Code's `file-code` icon with the tooltip and accessible
  label **Open Markdown Source**. Clicking it shows the editable Markdown.
- In source mode, show Zed's `eye.svg` with the tooltip and accessible label
  **Open Markdown Preview**. Clicking it renders the current buffer contents.
- Place the button at the right of the file-tab bar. It operates on the active
  Markdown document and stays visible when file tabs overflow. Hide it for
  other file types.
- Remember the selected view for the open document when switching tabs.
  Closing and reopening the document starts in preview again.
- Provide `:VSVimMarkdownToggle` as a keyboard-accessible equivalent of the
  button. Its description uses the same source/preview terminology.
- Switching views preserves the source cursor, source viewport, undo history,
  dirty flag, and unsaved contents. Preserve the preview scroll position when
  returning to an unchanged document; after edits, clamp the position to the
  updated document.
- Cmd-S and `:w` save the original Markdown file from either view. The existing
  modified marker and save/discard/cancel close prompt apply in both views.
  Rendering or switching views never saves a file or changes its text.

## Preview appearance and interaction

Render proportional document text with heading hierarchy, paragraphs,
emphasis, strong text, strikethrough, inline code, fenced code blocks,
blockquotes, ordered and unordered lists, task-list markers, horizontal rules,
links, tables, and images. Code blocks retain whitespace and use a monospace
font. Preserve Unicode text and support long paragraphs and long code lines
without breaking the layout.

Use the active editor theme for background, text, links, code blocks, and
borders. The preview fills the current file's editor area below the file-tab
bar while preserving the sidebar and status line. Hide the source minimap
while previewing and restore it when returning to source.

Wheel and trackpad scrolling move the preview. Links are clickable; document
anchors scroll within the preview, relative paths resolve from the Markdown
file's directory, and external links use the host's normal URL opener. Resolve
relative image paths from that same directory. Broken images leave readable
alternative text and do not prevent the rest of the document from rendering.

Preview is read-only. Pointer scrolling, clicks, text selection and copy act
on the preview and do not move the source cursor or send editing gestures to
the hidden source. Source editing resumes when the user selects Open Markdown
Source. Save, close, command entry, and file/sidebar navigation continue to work
while previewing. Raw HTML must not execute scripts or run commands.

## One buffer and pane ownership

Neovim retains the original file buffer throughout. Do not create a rendered
scratch buffer, duplicate file buffer, preview tab, split, browser window, or
separate editor session to implement the toggle.

Sprite draws the preview over the corresponding ordinary file window's content
rectangle. Other visible splits, sidebars, command-line prompts, popups, and
the status line keep their existing behavior. The implementation must carry
the target Neovim window identity and bounds rather than assuming that the
file occupies the entire redraw grid.

The view choice belongs to the open file buffer. If that buffer is visible in
multiple windows, each visible instance uses the chosen mode and retains its
own scroll position. Changing focus to another document updates the toolbar's
target. A delayed click or render result must not affect the newly focused
document.

## Component responsibilities

### VSVim

A built-in Markdown module owns Markdown detection, default preview policy,
the current view choice, source buffer/window identities, source text and
generation, source cursor/view preservation, and the toggle command. It
registers a provider with sprite.nvim alongside the existing tabs and minimap
providers. Read the current in-memory text so unsaved edits appear immediately
on returning to preview. Invalidate the preview when another editor action
changes the buffer or reloads it from disk.

### sprite.nvim

Add a negotiated optional native-grid capability, `grid-markdown-v1`. Reuse
the existing Surface connection, provider notifications, coalesced RPC pulls,
and revision-checked action pattern. Send document content separately from
lightweight target, geometry, theme, mode, and scroll updates. Keep one pending
snapshot request per session and service the latest invalidation afterward.

The implementation spec will define exact operation/event fields, content
limits and chunking, target-window bounds, generation/revision rules,
capability negotiation, teardown, and shared protocol fixtures before code is
written. Old hosts receive no Markdown operations. Ordinary terminals and
older Sprite hosts retain editable source; they must never show an empty pane
or advertise a nonfunctional toggle.

### Sprite

Own Markdown parsing, native document layout, painting, scroll state, preview
selection/copy, resource loading, and pointer hit testing. Use GPUI for the
rendered document and an established Markdown parser rather than writing a
Markdown grammar or copying an editor's rendering subsystem. Choose and pin
the parser version in the implementation spec after checking its official
documentation and compatibility with Sprite's toolchain.

Use the VS Code `file-code` glyph identified by
`vscode/extensions/markdown-language-features/package.json`'s
`markdown.showSource` command and the exact Zed eye shape in
`zed/assets/icons/eye.svg`. Package the SVG assets with required upstream
license attribution; tint them for the active theme.

The source grid remains alive behind the presentation. Route preview pointer
events to the preview and preserve ordinary source input after returning to
source. Native prompts and other editor overlays remain usable. Validate
document bounds, payload sizes, identities, and revisions before replacing
visible state. A stale update cannot replace another file's preview.

## Responsiveness and failures

Parse and prepare document updates away from the input/paint path. Reuse the
parsed document while scrolling and discard work belonging to a previous
buffer generation. Bound snapshot construction, transport, decoded images,
and rendered-document caches. Large documents must leave the toggle and
source editing usable; define measured budgets and a readable fallback in the
implementation spec.

An unavailable renderer, failed parse/resource load, or unsupported host must
leave access to the original source intact. Show a useful reason for a failed
preview rather than silently displaying another document or dropping text.
Buffer disposal, window closure, filetype changes, host disconnect, and editor
shutdown release preview state and pending work. Theme and pane-size changes
reflow the current document without modifying the source.

## Acceptance checks

1. Open a Markdown file from startup, Explorer, and a file tab. Each new file
   opens in preview with one listed file buffer and one tab.
2. Click file-code, edit without saving, and click the eye. The preview shows
   the unsaved text. Return to source and verify the buffer ID, dirty flag,
   cursor, viewport, and undo/redo history are preserved.
3. Switch between Markdown and ordinary files. Verify remembered view choice,
   correct icon/tooltip, a reachable button with overflowing tabs, and no
   preview or button on ordinary files.
4. Save and close from both modes. Verify original file contents, modified
   markers, save failures, and save/discard/cancel behavior.
5. Render a fixture containing every supported Markdown element, Unicode,
   relative images and links, broken images, long paragraphs, and wide code
   blocks. Verify theme changes, resizing, scrolling, selection/copy, and
   document anchors in an actual native Sprite window.
6. Verify preview interaction does not edit or move the hidden source. Check
   command entry, prompts, sidebar navigation, split windows, minimap hiding
   and restoration, and returning focus to editable source.
7. Edit/reload a document while it is previewed, switch files during rendering,
   close the target window, and disconnect the provider. Verify obsolete work
   is discarded and source text remains intact.
8. Use shared bridge/host fixtures for valid and invalid operations, negotiated
   support, stale actions, bounds, and teardown. Verify fallback with an older
   host and a normal terminal.
9. Measure initial preview, an edit-to-preview update, and scrolling for small
   and large Markdown documents. Capture actual native screenshots and record
   the host/adapter revisions used for the checks.

## Delivery and planning

Implement on coordinated feature branches in VSVim, sprite.nvim, and Sprite.
Verify the protocol and renderer, then the bridge and VSVim policy. Update
VSVim's adapter pin only after the tested adapter revision is available. Build
a test Sprite application and document how to run the feature without replacing
the user's running editor.

After written PRD review, harden the design against CONTEXT.md and record the
ownership decision in an ADR. Create the technical spec under docs/TSPs with
the exact protocol, renderer dependency, file changes, test commands, and
performance checks before implementation.

## Source anchors inspected

- VSVim: `lua/vsvim/init.lua`, `lua/vsvim/tabs.lua`,
  `docs/PRDs/10-19-2026-native-minimap.md`, and
  `docs/adr/0002-native-minimap-ownership.md`.
- sprite.nvim: `lua/sprite/adapter.lua`, `lua/sprite/tabs.lua`,
  `lua/sprite/minimap.lua`, and `lua/sprite/input_bridge.lua`.
- Sprite: `crates/sprite-app/src/surface/grid.rs`, `surface/tabs.rs`,
  `surface/wire.rs`, `terminal_view/native_tabs.rs`, and
  `terminal_view/surfaces.rs` under that crate's `src` directory.
- VS Code: `extensions/markdown-language-features/package.json`.
- Zed: `assets/icons/eye.svg`.
