# Native Markdown protocol v1

Negotiation: `grid-markdown-v1` in Surface capabilities and opened features.
Transport: existing grid Surface JSON messages, `type: "markdown"`. Every
operation has a connection-monotonic positive safe-integer `revision`.
All identifiers and generations are positive JavaScript-safe integers.
Unknown fields and invalid values are refused atomically.

## Document

```json
{"type":"markdown","kind":"document","revision":1,"buffer":1,"generation":3,"path":"/project/README.md","text":"# Hello\n"}
```

`buffer` is the original Neovim buffer ID. `generation` is its changedtick;
`path` is the full filename (empty for unnamed buffers), at most 4096 bytes.
`text` is current source, at most 2 MiB UTF-8. This fits the 16 MiB transport
limit even with worst-case JSON escaping, so document chunking is unnecessary.
The provider extracts at most 256 lines per scheduled callback and cancels
when changedtick changes. Do not read or resend text on cursor or scroll moves.
Host retains at most 16 documents and 32 MiB source total; old unreferenced
documents are evicted. Parsed layout work is asynchronous and keyed by
buffer/generation so obsolete results cannot replace a newer document.

## State

```json
{"type":"markdown","kind":"state","revision":2,"active":1000,"windows":[{"window":1000,"buffer":1,"generation":3,"preview":true,"row":0,"column":0,"width":80,"height":22}],"colors":{"background":"#1e1f22","foreground":"#bcbec4","muted":"#9da0a8","accent":"#589df6","code":"#2b2d30"}}
```

At most 16 ordinary visible Markdown windows. `active` is a window ID in
`windows`, or null when another file/sidebar owns focus. `row` and `column`
are zero-based global Neovim grid coordinates, excluding native tabs; dimensions
are positive and all rectangles fit the current grid. Exclude winbar/statusline
and source gutters from the content rectangle. `generation` names the current
buffer text; preview is painted only if that document generation is available.
Source windows remain in state with `preview:false` so the toolbar can show
the eye. Colors are exactly #rrggbb. Native minimap space is suppressed when
the active Markdown window is in preview.

Empty windows hides presentations and toolbar without changing source. During
command entry or editor prompts/float popups, send empty windows to let the
normal editor grid show the prompt. Restore state when ordinary editing resumes.
Source/preview mode belongs to the buffer; scroll state belongs to each window
and buffer pair. Keep up to 64 scroll entries to bound retained tab history.

## Hide

```json
{"type":"markdown","kind":"hide","revision":3}
```

Clear documents, visible state, and pending parse work on provider failure or
detach. Source remains usable. A state operation may precede its document;
show readable loading feedback in that window until the matching text arrives.

## Events

```json
{"type":"markdown_action","revision":2,"window":1000,"buffer":1,"generation":3,"action":"toggle"}
```

The action revision is the latest state revision, independent of later
document operations. Validate revision, window, buffer, generation, visibility,
and current target against live Neovim state before toggling. Never use a
delayed action to change a newly selected file. Toolbar uses VS Code file-code
in preview and Zed eye in source. Link navigation may send the same envelope
with `action:"open"` and `destination` containing the Markdown link destination;
fragment-only anchors stay in the host. Provider resolves local file paths
against the source directory and opens them using Neovim APIs, never shell text.
External http/https/mailto links use the host URL opener.

## Input

Native preview consumes pointer/scroll/selection/copy; no preview pointer
gesture reaches the grid. The bridge's ordered pre-input hook checks
`sprite.markdown.before_input(event)` before the minimap restoration hook.
Return false to consume an edit/paste aimed at preview. Return true in source
or command/prompt mode, for command entry (`:`), save, Escape, and existing
sidebar/window navigation shortcuts. This keeps the buffer modifiable for
agent edits and `:w`, without making the hidden source writable through preview.
Hooks must release blocking native commands without trapping continuation keys.

## Fallback and limits

No provider or unsupported capability means no operations, preview input gate,
or toolbar. Documents exceeding 2 MiB stay in source with a readable reason.
Asset loading is bounded and failure displays image alternative text. Do not
execute raw HTML, scripts, or non-file/non-web resource schemes.
