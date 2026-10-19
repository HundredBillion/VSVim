# Native minimap Surface extension v1

Planning contract for issue #8. Both implementations consume this contract's
fixtures; this document does not advertise an implemented capability.

## Negotiation and identities

`opened.features` and capabilities advertise `grid-minimap-v1` only in a host
that implements the operations below. A bridge sends these operations only when
that feature is present and an editor provider is registered. Every operation
is an existing grid operation, standalone or inside `batch`, with type `minimap`.

Every message has `revision`, a positive JSON-safe integer strictly increasing
for the Surface connection. Revision advances only on successful validation.
`target` is an opaque nonempty string of at most 128 bytes, unique for the editor
buffer/window incarnation. `generation` is a positive safe integer advancing
when source, theme, or display options change. Window switches allocate a new
target even when two windows show the same buffer. Old actions are ignored.

Coordinates: source lines are 1-based; ranges `[start,end]` are inclusive; text
span offsets `[start,end)` are zero-based UTF-8 bytes of the transmitted line.
Colors are six-digit `#rrggbb`; opacity and layer order belong to the renderer.
Source text has tabs expanded using Neovim display columns, no line terminators,
and is clipped to 256 display cells and 2,048 UTF-8 bytes, stopping at a character
boundary. This clipping affects miniature display only, not word matching/diffs.

## Source transactions

A `begin` establishes a transaction. `base` is null for a complete replacement,
or the currently committed generation for a splice. `start` is a 1-based source
line in the old document; `delete` old lines are replaced by `insert` new lines.
`total` is the resulting source line count. Full replacement uses start=1,
delete=0, insert=total, base=null. Neovim buffers always contain at least one line.
`palette` defines up to 256 colors; index 0 is the ordinary foreground.

```json
{"type":"minimap","revision":1,"kind":"begin","target":"b7:w3:1","generation":1,"base":null,"start":1,"delete":0,"insert":3,"total":3,"palette":["#bcbec4","#cf8e6d","#6aab73"],"background":"#1e1f22"}
{"type":"minimap","revision":2,"kind":"lines","target":"b7:w3:1","generation":1,"offset":0,"lines":[{"text":"local title = 'hello'","spans":[[0,5,1],[14,21,2]]},{"text":"","spans":[]},{"text":"return title","spans":[[0,6,1]]}]}
{"type":"minimap","revision":3,"kind":"commit","target":"b7:w3:1","generation":1}
```

`offset` counts inserted lines already supplied, starting at zero; chunks must
be contiguous, nonempty, contain at most 256 lines and encode to at most 256 KiB
including the envelope. A line has at most 256 sorted nonoverlapping color
spans with valid UTF-8 endpoints and palette indices. Unspanned text uses index 0.
Adjacent spans with the same color are merged before transport.

A new begin cancels an incomplete transaction. Its generation must exceed both
committed and pending generations. A commit requires exactly `insert` staged
lines. For a splice, total=old_total-delete+insert, deletion must fit, start can
be old_total+1 only for append, and target/base must match committed state.
Palette/background must equal committed values for splices; palette changes
require full replacement. Recoloring an unchanged line is a same-length splice.
Coalesce multiple outstanding edits into one contiguous replacement region;
restart with a replacement when coalescing cannot safely rebase on committed data.

Validate each operation before mutation. Commit swaps complete staged state
atomically. On a target change, immediately stop drawing old source/overlays
while replacement stages. On an edit to the same target, retain committed code
until commit, clear overlays during staging, and disable stale pointer actions.
Do not reuse old source colors with new line numbers. A rejected chunk leaves
previous committed code intact; the bridge cancels with hide and restarts after
logging the refusal. A state notification for uncommitted data is rejected.

## Lightweight state

```json
{"type":"minimap","revision":4,"kind":"state","target":"b7:w3:1","generation":1,"viewport":[1,2],"selection":[2,3],"occurrences":[1,3],"changes":[{"start":1,"end":1,"kind":"added"},{"start":3,"end":3,"kind":"modified"}],"word":"title"}
```

`selection` is null or a source row range. `occurrences` is a sorted unique array
of rows. `changes` is sorted by start, nonoverlapping, kind added/modified/deleted;
end>=start and all positions fit total. A deletion is a single surviving
boundary line with start=end. `word` is null or a string <=1,024 UTF-8 bytes.
State replaces all overlays; omission of a required field is an error.
Viewport is mandatory, ordered, and clamped to buffer rows. The host derives
colors, viewing rectangle, long-file map window, and tooltips from this state.

```json
{"type":"minimap","revision":5,"kind":"hide"}
```

Hide clears all source, staged data, overlays and strip width, while retaining
the revision watermark for the connection. Unsupported buffer types use hide.
The 480-pixel width threshold is applied by the host without discarding cached
source, so widening the pane restores current code without a provider reload.

## Actions back to the editor

```json
{"type":"minimap_action","revision":4,"target":"b7:w3:1","generation":1,"action":"reveal","line":3}
{"type":"minimap_action","revision":4,"target":"b7:w3:1","generation":1,"action":"scroll","topline":2}
```

Revision here identifies the last committed source operation or subsequent
accepted state operation represented by the pointer event. The bridge remembers
the greatest revision actually forwarded. Accept actions for the current target
and generation with revision between its commit and last-forwarded revision;
state-only progress must not invalidate an in-progress drag. Validate positive
in-range line/topline values. Reject other actions/fields before invoking provider.
Coalesce continuous drag/wheel events to one per animation frame; final pointerup
flushes the final position. Reveal centers a line; scroll sets a source topline.
Both invoke selection-preserving browsing in VSVim and keep keyboard focus in
the editor. They contain no executable text or filesystem paths.

## Native mapping

Let N=source line count, H=min(strip content height,N*3), h=3 logical pixels, and
v=visible source row count clamped to 1..N. The miniature window displays
M=min(N,max(1,floor(H/h))) rows. With editor top row t, its source offset is
`floor(clamp((t-1)/max(1,N-v),0,1) * max(0,N-M))`. Paint source lines offset+1
through offset+M. Clicking y reveals clamp(offset+floor(y/h)+1,1,N), unless the
clicked row belongs to a change, in which case reveal the hunk start.

For N>v, the drag thumb has height min(H*0.8,max(min(12,H),v*h));
for N=v it fills H. This leaves a drag track even in a very short pane. It
travels over H-thumb_height. Its top is `(t-1)/max(1,N-v)*(H-thumb_height)`. Map drag position
back through that full-file track, not through the moving miniature window;
use the original pointer-to-thumb offset and clamp to first/last editor top.
Draw one viewing rectangle using that thumb geometry, with a translucent fill
and a distinct outline. Its minimum height is a pointer target allowance; it
must remain visually distinct from the blue selected-row section. Wheel deltas map to source topline
changes using existing host scroll accumulation, with no underlying grid event.

## Bounds and failure behavior

- At most 1,000,000 source lines and 64 MiB committed text/span storage per Surface.
- At most another 64 MiB staged; reject before allocation exceeds that bound.
- Up to 100,000 occurrence rows or change groups per state; total state <=4 MiB.
- The general Surface limit remains 16 MiB per message; minimap limits are lower.
- Safe integers only; reject fractions, negative numbers, overflow and malformed UTF-8.
- A provider exceeding document/state bounds hides the minimap and emits a
  once-per-buffer warning; it never disables editing or silently truncates rows.
- Disconnect/teardown releases both committed and staged state.

## Required fixture cases

Copy the successful begin/lines/commit/state/hide sequence above into
`tests/fixtures/minimap-v1.json` in sprite.nvim and an identical fixture under
`crates/sprite-app/tests/fixtures/minimap-v1.json` in Sprite. The fixture envelope
is `{ "valid": [messages], "invalid": [messages] }`. Invalid entries are tested
independently against fresh committed state from the first four valid messages (before hide), with a new revision:
unknown action/kind, stale generation, incorrect base, noncontiguous chunk,
out-of-range line, duplicate occurrence row, invalid color index, UTF-8 midpoint,
more staged lines than insert, and commit before all chunks. Tests assert the
committed snapshot and revision are unchanged after each refusal.
