# Architecture and performance evidence

The October 16 architecture pass separates native editor font metrics from terminal metrics, retains Explorer data between openings, reduces SCM refresh work, and avoids rebuilding unchanged tab metadata.

| Path | Before | After | Measurement boundary |
| --- | --- | --- | --- |
| Warm Explorer first rows, four trials | 7.15–8.30 ms | 1.53–2.42 ms | Real Projects filesystem, scheduled fake host acknowledgements; no Sprite paint |
| Twelve saves in a two-repository scope | 2 discoveries, 4 repository scans | 0 discoveries, 1 targeted scan | Deterministic event/job-count fixture |
| Twelve focus events in a two-repository scope | 2 discoveries, 4 repository scans | 0 discoveries, 2 repository scans | Deterministic event/job-count fixture |
| First edit, native tabs | 2 provider calls | 1 provider call | Embedded Neovim through real adapter, fake host |
| Twelve additional dirty edits | 12 provider calls | 0 provider calls | Same adapter fixture |

Cold Explorer first rows were 27.32 ms before and 10.62 ms after, but filesystem-cache state was uncontrolled; these values do not establish a cold-start improvement. The warm harness closes at initial readiness, so separate controller tests verify completed background refresh and filesystem changes while hidden. A portable-harness rerun during concurrent integration installation measured 5.11–8.26 ms warm first rows; after installation it measured 1.51–2.35 ms. Each run used four warm trials and the same 28-row root, matching the original before/after row counts. Concurrent system work and uncontrolled filesystem caches make these samples unsuitable as a stable speedup or user-visible latency guarantee.

SCM repository scans peak at four in the fifteen-repository fixture. Each scan still runs its Git commands sequentially. Explicit refresh/reopen rediscovers repositories; a newly nested repository inside an already known repository may need that explicit refresh. Failed discovery retains the previous displayed entries.

Native tabs retain guarded text-change events because automatic edits do not consistently emit OptionSet. Cheap modified-state comparisons still run, bounded by the native tab target limit. Save, undo, redo, rename, close, theme and background-buffer edits remain covered. Provider counts are not measurements of frame time or typing latency.

## Reproduce

From this VSVim checkout, run the first-rows benchmark with an explicit SVGTree checkout and filesystem root:

```sh
/path/to/nvim -u NONE -i NONE -l tests/explorer_benchmark.lua /path/to/svgtree.nvim /path/to/root
```

It emits five JSON records (one initial opening and four warm openings). `first_rows_ms` measures the first rows request and `focus_request_ms` observes the focus request, not its acknowledgement or visible paint. The Sprite API is a scheduled fake host; no Sprite process or sprite.nvim checkout is required. Use the same root and runtime to compare revisions. Initial opening does not mean an OS-cold filesystem. Each trial closes immediately at the focus request, potentially cancelling background refresh; controller regressions separately cover refresh completion.

Recorded revisions: SVGTree `cbf3302` → `bb38c8c`, SCM `ca4c814` → `1fd6895`, sprite.nvim `24d0ea0` → `010f898`. Timings came from one local macOS Projects directory with 28 rows and Neovim `v0.13.0-dev-761+g0639f6e41a`; they are illustrative samples, not latency guarantees.

Use the actual Neovim 0.13 nightly binary with `-u NONE -i NONE`, rather than a wrapper that loads VSVim implicitly.

Run each plugin suite from its own checkout:

- SVGTree: `SVGTREE_NVIM=/path/to/nvim SVGTREE_API_CHECKOUT=/path/to/sprite.nvim bash scripts/test.sh`.
- SCM: `nvim -u NONE -i NONE -l tests/refresh_policy_test.lua`, then `refresh_events_test.lua` and `refresh_races_test.lua` in the same directory. The policy test records scoped scan bounds, events test covers bursts, and races test covers newer results during discovery and initial cache population.
- sprite.nvim: `nvim -u NONE -i NONE -l tests/run.lua`. Native-tab regressions count provider work through the embedded adapter.

## Unresolved shortcut report

The reported Cmd+E action is not yet identified. No `<D-e>` mapping was present in the inspected VSVim session. Space-e toggles Explorer; Ctrl+Shift+E splits Sprite downward. These improvements do not establish a fix for Cmd+E or measure its input-to-visible-paint time. Track confirmation and an end-to-end reproduction in [VSVim issue 3](https://github.com/HundredBillion/VSVim/issues/3).

## Independent fonts

Sprite's `[font]` controls terminal text. Optional `[surface_font]` controls native editor text. If omitted, native editor text follows `[font]`; an explicit section has its own defaults for omitted fields. VSVim's bundled profile sets both to Menlo 12 with line height 1.5. Native UI labels retain their system font. Reload and zoom tests cover independent geometry; physical macOS IME-panel appearance and Linux runtime remain unverified.

Tracking: [VSVim issue 4](https://github.com/HundredBillion/VSVim/issues/4).
