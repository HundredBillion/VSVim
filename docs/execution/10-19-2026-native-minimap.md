# Native minimap execution evidence

The final pinned release run passes every recorded performance gate at 1,000,
10,000 and 100,000 lines. Same-release native interaction assertions and
screenshots are captured. Whole-branch code/evidence review approved the measured revisions. A later
undo-only correction is also approved; the published dependency pin awaits its
delivery-only scoped review. This
report does not declare merge readiness. Dependency feature branches are
published, including the separate Sprite PR120 Cmd-C delivery dependency.
No push, merge, installation or issue closure was performed here.

| Repository | Measured code revision |
| --- | --- |
| VSVim | `95ffdcb252ce419c6dca97d1adf32a527519ff0d` |
| sprite.nvim | `bb309536778274f9e2d9519f6a25d9e8f28baecf` |
| Sprite | `386f8c599eb5c7d37c91fab15132bbc09ea9442a` |

Code was committed before the release build. Evidence/status documentation and the later explicitly identified undo-only
correction/pin below changed afterward. Neovim was 0.13.0-dev-761+g0639f6e41a, LuaJIT2.1.1774896198
on this development Mac. The committed build command passed in 15.89s:

```
cargo build -p sprite-app --bin sprite --features minimap-benchmark --release --locked
```

The optional benchmark feature timestamps/enqueues events on measured paths;
one logger thread owns the cached file and performs JSON serialization/I/O.
There is no product QoS change. From VSVim, the single final attempt was:

```
uv run --with pynvim python tests/minimap_benchmark.py --output /tmp/vsvim-minimap-native-pinned-round3 --sprite /Users/davidlee/Projects/Sprite/target/release/sprite --focus
```

Complete result arrays, native event traces, editor callback metrics and query/
worker status are preserved under [pinned-round3](native-minimap/pinned-round3/).
Each size has one process-cold initial sample, one same-process warm sample,
30 predetermined first-visit prewarm scrolls, 30 measured repeats of the same
region, and one actual edit-to-updated-Git-band sample. Paint sample counts,
including frame work during the warm interval, are in each result JSON.

| Lines | First painted cold / warm(ms) | Warm scroll p95(ms) | Canvas CPU paint p95(ms) | Whole owned callback max(ms) | Updated Git-band paint(ms) |
| --- | --- | --- | --- | --- | --- |
| 1,000 | 78.032 / 75.971 | 23.781 | 2.045 | 0.900 | 54.737 |
| 10,000 | 531.395 / 458.467 | 29.319 | 2.084 | 2.062 | 59.451 |
| 100,000 | 8662.753 / 8000.403 | 14.074 | 2.076 | 3.173 | 243.174 |

All sizes pass the unchanged gates: <=4ms whole minimap-owned scheduled editor
work, <=256KiB source chunks, zero source messages on pure scroll, <=8ms warm
canvas paint p95, <=33ms warm native input-to-changed-paint p95, initial
0.5/2/10s, and actual updated Git-band 250/250/1000ms. Native timing begins at
handler dispatch, excluding the helper's 100ms polling. Initial timing begins
at source activation, not full application cold startup. Paint means CPU canvas
submission completion, not GPU/compositor presentation. Updated-band timing
requires a changed-generation paint with the actual visible first-line modified
HEAD band; source-only repaint timing remains separately recorded.

| Lines | Cold source / complete sync(ms) | Warm source / complete sync(ms) | First-visit prewarm p95(ms) |
| --- | --- | --- | --- |
| 1,000 | 55.058 / 59.917 | 55.886 / 60.926 | 25.477 |
| 10,000 | 471.608 / 513.497 | 392.345 / 442.281 | 16.037 |
| 100,000 | 8207.486 / 8644.178 | 7544.673 / 7986.935 | 14.217 |

Fixtures are valid repeated Lua with real HEAD additions/modifications/deletions,
actual distribution syntax colors, safe query configuration and the default
worker active. Each run uses isolated copies of installed plugins and Mason
packages; no installed dependency is modified. Readiness requires initialized
LSP clients, empty progress and unchanged diagnostics for 1s, with a 30s timeout.
All sizes reached quiet; complete observations are retained. Every scroll
records active/key/unoccluded AppKit metadata and actual paint active=true.
Cold means process-cold with OS caches uncontrolled; warm means same-process
repeated source. Only a physical 2x display was available. Physical 1x, IME and
other platforms were not exercised.

Rust builds/tooling were idle before timing. Several existing user Python
processes were each consuming approximately 74–78%CPU during preparation; they
were preserved. No other tests/builds ran concurrently with the final native
measurement. This load qualification is retained even though the final gates
pass.

| Lines | Largest chunk(bytes) | Source bytes(cold+warm+edit) | Peak host/editor/worker(KiB) |
| --- | --- | --- | --- |
| 1,000 | 20,317 | 158,330 | 105,136 / 50,384 / 26,368 |
| 10,000 | 20,830 | 1,623,094 | 105,552 / 121,376 / 73,200 |
| 100,000 | 21,343 | 16,629,780 | 127,760 / 696,144 / 545,776 |

RSS is 100ms macOS libproc sampling, following all discovered owned worker
restarts. Peaks are independent per-process maxima, not an aggregate or an
allocation bound. The 100k editor includes ordinary LSP/highlighter work. During
100k initial preparation 150 RPC heartbeats were serviced: p95
4.610ms, max 10.326ms; all samples are retained. This verifies
service during preparation, not only individual callback duration.

Prior failures remain preserved. [Pinned round2](native-minimap/pinned-round2/)
reported 1k 33.867ms warm scroll p95 against 33ms; its worst 34.489ms sample had
flush 2.168ms, socket write 2.205ms, host state receipt 22.201ms and paint 34.489ms.
The final code immediately flushes the first wheel event and coalesces following
events until the next frame. Earlier [pinned-final](native-minimap/pinned-final/)
100k 35.105ms and [round1](native-minimap/pinned-round1/)
56.036/53.686/61.673ms misses remain labeled failures. Original generation-only
edit timing and round1 incomplete worker memory are superseded by actual-band
and corrected libproc measurements, not retroactively relabeled passing.
The earlier WIP 100k first-visit 62.746ms miss/repeated-warm 27.148ms diagnostic
is also retained in the task report and is not a final sample.

## Actual native interactions

[Final native artifacts](native-minimap/final-native/) use the same committed
release and contain screenshots, action/assertion JSON and reproduction scripts.
Screenshots were visually inspected; all assertions passed:

- Native doubleclick selects `file`, with 14 occurrence rows, blue selected row 1
  and a real HEAD modified band. Selected rows 13–27 overlap a real addition.
- Actual resolved light-theme colors appear in the editor and tiny code.
- A supported native SVGTree dock, rooted explicitly at the isolated fixture,
  narrows the editor below 480px and hides the strip. Closing it restores the
  editor layout. This proves the narrow surface route without claiming that
  ignored 420/937px window resize requests succeeded.
- After selecting original rows 1–3, native minimap click browses to top 192,
  bottom 232 while preserving selection [1,3]. Actual native Cmd-C copies those
  original lines plus the linewise trailing empty entry into an isolated
  in-memory clipboard provider; no system clipboard access. Native `x` after
  another browse removes exactly the original three rows, verified by old row 4.
- One continuous held native thumb drag on 100k lines reaches
  top 99954/bottom 100000, then top 1 on the return drag. Wheel events are exercised
  by all 90 measured warm samples, in addition to 90 prewarm samples.

The narrow follow-up reused only owned fixture dependencies, disabled swap for
that diagnostic, and used a unique RPC socket. A stale reused fixture socket/
swap prompted discarded setup attempts; these are excluded as evidence. All
owned fixture processes were closed. Earlier root screenshots under
[prior provenance](native-minimap/) are supplementary, not replacements for
these final artifacts.

## Focused verification and limits

The final protocol/input group passed actual folded-source 128 acknowledgments,
provider bounds/lifecycle 2sections, setup integration 5tests (36.209s), adapter
149checks, native minimap 11tests (4.77s), wire 16tests, Rust formatting, adapter
stylua and diff checks. Earlier affected source 7sections, real worker differential/
query/cancellation/control cases, integration 5, adapter 135, host control parser
and 64MiB boundary tests passed before this final navigation-only group.
Unchanged selection 21(including exact 100k yank) and Git 13 checks remain applicable.
The parent independently ran `python3 scripts/check_findings.py` from Sprite:
`every finding is guarded by a test or tracked by an issue`, exit0. Exact commands/results and review rounds are in the task report.

Existing pynvim Python 3.12 child-watcher deprecation, GPUI float-fallback,
dependency future-incompatibility and helper AppKit activation deprecation
warnings remain. The new unused getter warning was removed. Configured external
query object ownership/custom Lua handlers, preloaded query modules, or
unsupported capture bounds select the exact foreground fallback to preserve
colors and mutation semantics. Default-worker budgets do not qualify that
fallback's performance. See ADR0003 for the installed-runtime reader boundary
and ADR0004 for negotiated processed-action acknowledgments. Whole-branch code/evidence review is approved. The undo correction is also approved; the delivery-only pin review remains
pending.


## Published pin and final undo correction

Evidence is committed at VSVim 51353d7982c7f349c113a119e5ddba659ead2200.
The measured source remains 95ffdcb. Subsequent source correction
`672501a8a8e1c956875eab16d62610b9d5f983e4` adds only the provider's
`on_changedtick` handler: undo/redo advances the tick again after `on_lines`, so
in-flight version-guarded preparation must restart at the final tick. Idle
committed tick notifications perform no extraction. The normal API edit,
initial and scroll paths measured above are unchanged; no native performance
rerun was made or implied for the later correction.

Real-provider edit/save/undo/redo source text and HEAD bands now pass through
both the actual worker and exact-main fallback. The worker test also compares
its full child mirror to main after each step. Provider bound/lifecycle checks
pass. Post-fix setup integration against the fresh remote adapter passes 5 tests
in 24.849s. [Focused raw outputs](native-minimap/final-provider/) are retained.
Dedicated native soft-wrap interaction was not exercised; the documented
mapping axis is logical buffer lines, with existing source/geometry coverage
for empty, short, long, tab, Unicode and folded cases. Native undo keystroke
routing was not independently replayed; this check exercises actual provider
content/bands and built-in undo/redo, complementing the tested native input path.

Parent published the feature branches. [Adapter PR7](https://github.com/HundredBillion/sprite.nvim/pull/7)
uses exact bb309536778274f9e2d9519f6a25d9e8f28baecf; its seven CI checks were
reported successful by the parent. [Host PR121](https://github.com/HundredBillion/Sprite/pull/121)
uses 386f8c599eb5c7d37c91fab15132bbc09ea9442a and is stacked on
`fix/native-editor-copy` for PR120. Remote `git ls-remote` returned the exact
adapter feature-branch SHA; a fresh temporary Git repository fetched that SHA
with `--depth=1`, checked out FETCH_HEAD detached and verified HEAD equality.
Installed plugins were untouched. VSVim's adapter dependency now pins that
published SHA. The later pin/documentation commit is delivery bookkeeping and
is separate from measured source provenance. The undo correction is independently approved; final narrow pin review is
pending; no merge or installation was performed.
