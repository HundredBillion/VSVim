# Independent whole-feature review

Reviewed coordinated diffs VSVim d3a396f..1ea550b, sprite.nvim 3c1be34..6ae5a61, Sprite 1000412..8804fe3 against approved PRD, TSP and native-markdown-v1 protocol. Read-only repository review; diagnostic artifacts only in /tmp. Existing full-suite evidence was not rerun.

## Findings

1. **P2 — Valid linked images and table images never render.** Sprite `crates/sprite-app/src/terminal_view/native_markdown/document.rs:96` and `:140`. The parser sets `standalone = !in_table && link.is_none() && images.is_empty()` and only records `block.image` when that flag is true. Consequently `[![logo](logo.png)](next.md)` and `| ![logo](logo.png) |` table cells always become alternative text, even with a valid supported local image. `Prepared::load` only visits blocks with `image.is_some()`, so this bypasses resource loading entirely. Linked badges and screenshot thumbnails are common Markdown, and the PRD promises rendered images without restricting their placement. Preserve image ranges/metadata inside links and cells while retaining the range-crash fixes; verify with an existing small PNG, including clickable linked images.

2. **P2 — URL-escaped relative image filenames resolve to the wrong file.** Sprite `crates/sprite-app/src/terminal_view/native_markdown/document.rs:236`. `resource_path` passes the Markdown destination directly to `Path::new` without decoding percent escapes. For an actual file `/tmp/my image.png`, `![caption](my%20image.png)` resolves to `/tmp/my%20image.png` and displays the alternative text. The VSVim link resolver already calls `vim.uri_decode`, so a link and an image targeting the same escaped filename behave differently. Decode the local URI path (with invalid/NUL handling) before filesystem lookup and cover spaces and Unicode escapes. Standalone probe confirms the current literal escaped result.

3. **P2 — Nested emphasis loses its outer style after the inner span.** Sprite `crates/sprite-app/src/terminal_view/native_markdown/document.rs:132`. Emphasis/strong/strike are tracked as booleans; closing an inner tag clears the style even while an outer tag of the same type is still open. Valid `*outer _inner_ tail*` produces an italic first and inner span, followed by a plain ` tail` span. Preserve nested style depth or restore prior style on closing tags. The same issue applies to nested strong delimiters; table-header bold also shares this state. Probe output demonstrates the wrong final span.

## Diagnostic evidence

- `/tmp/vsvim-markdown-review-probe.rs`: copies the production parser module verbatim (without its tests), then prints the parsed forms of the three compositions above and escaped resource-path resolution.
- Compiled using the existing pinned pulldown-cmark rlib from `/Users/davidlee/Projects/Sprite/target/debug/deps`; production sources unchanged.
- `/tmp/vsvim-markdown-review-probe.log`: actual output confirming image metadata is absent, escaped path remains escaped, and outer emphasis is lost.

## Integration/spec verdict

The reviewed architecture follows one-buffer/two-view ownership, negotiated capability, window identity and rectangles, changedtick generations, state-revision actions, ordered input gating, bounded documents/parsing/image loads and original-source save paths. No additional confirmed source-corruption, identity, protocol or startup cause was found in this pass. The provider's blanket URI-scheme rejection also means a host-forwarded `file://` link does nothing; that is a cross-layer inconsistency worth clarifying, but the mandatory relative-path behavior is independently covered by finding 2.

**Not fully complete against the approved PRD/TSP yet:** fix the concrete rendering defects above and retain the parent-owned actual desktop startup, screenshot and live interaction acceptance checks. Passing existing suites establishes substantial automated coverage but does not replace those explicit native acceptance requirements. No approval or merge readiness is claimed.

## Follow-up: provider file URI fix

Reviewed `/tmp/vsvim-markdown-provider-uri-fix.diff` (VSVim ff382e7) and the provided passing `/tmp/vsvim-markdown-provider-tests.log`. The provider now uses the installed nightly Neovim's `vim.uri_to_fname` for host-forwarded `file://` links, preserving fragment stripping, percent decoding, decoded control-character rejection, and API-based escaped file opening. The regression opens a real spaced filename via file URI and restores the original buffer. No substantive finding in this follow-up. The earlier file-URI inconsistency is resolved.

Root reports the live native startup problem was isolated-profile setup (lazy rejected symlinked plugin directories), resolved by copying those dependencies. Actual host/RPC now verifies default preview and toggle to source in buffer 1; OS screen-capture permission is denied, so screenshots remain unavailable and must be disclosed. Those latest live results are root-owned evidence, not an independent rerun by this reviewer. Host fixes for findings 1–3 remain pending a follow-up diff at this point.

## Final follow-up: host renderer fixes

Reviewed `/tmp/vsvim-markdown-host-final-fix.diff` (Sprite 8804fe3..632e028), including the parser metadata, image preparation/cache keys, native image pointer handling, block/table-cell rendering, resource resolver, style-scope restoration, and callers. **All three original P2 findings are resolved; no new substantive finding in the follow-up.**

- Linked/table images now retain source ranges, resource destinations and enclosing link destinations. Their decoded assets are keyed by block/image index, rendered inside the correct cell, and native handlers focus the preview and consume pointer input before following the link. Empty alternative text remains representable.
- Resource paths now percent-decode UTF-8, preserve literal plus signs, strip query/fragment suffixes, and reject invalid escapes and NUL.
- Nested emphasis restores the previous inline style from a stack, including an enclosing table-header style.

Independently rebuilt a temporary probe from the updated production parser module and rechecked all original reproductions: each now passes (`/tmp/vsvim-markdown-review-fixed-probe.rs` and matching executable). No repository changes and no duplicate full-suite run. Inspected the red regression evidence, focused native result (14 passed), and complete native library result (833 passed, 0 failed, 1 ignored). Native tests exercise encoded PNG loading, linked image destinations, table-cell containment, unlinked image clicks, empty alternative text, and absence of leaked grid mouse events.

### Final review verdict

**Code review clear across the reviewed coordinated changes, including the provider URI fix and all renderer follow-ups. No remaining concrete code blocker found.** The implementation now meets the reviewed functional/protocol requirements supported by the automated and native event evidence. The latest root-owned live acceptance trace inspected here used host 8804fe3 and confirms preview/source transitions retaining buffer 1 with no warnings/refusals. Root plans the same live check against 632e028 before final delivery. Actual screenshots remain unavailable because OS screen-capture access is denied; report that explicit PRD acceptance evidence limitation rather than claiming screenshot completion. This review does not independently certify unobserved desktop interactions or waive that limitation.

## Root live acceptance after review

Host632e028 was subsequently launched in a real native window with the final adapter/provider. The original buffer1 remained active across preview/source transitions, with no Surface warnings or refusals. See live-acceptance.json and live-markdown.jsonl. Screen capture remained unavailable; no screenshots are claimed.
