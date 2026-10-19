# Final input fix review

No blocking findings in commit 84c73ca (`Keep typing responsive while preserving minimap selections`). Working tree was clean during review.

The adapter owns actual key delivery, the provider hook owns no key, and per-entry delivery guards prevent late hook/mode callbacks from duplicating input. Pending hooks retire before later browse/tab actions, protecting newly preserved selections from stale restoration. Closed bridges reject new work and suppress late delivery. Mode callbacks now validate result shape, addressing the previous vim.NIL indexing issue.

The queued-input bypass intentionally retains native fast-input priority during modal waits; the comment and real-adapter baseline test now make that contract explicit. This agrees with the independent direct-Neovim probe from the preceding review. A mode reply is correctly not described as a key-consumption acknowledgment.

The new isolated tests cover hook/mode callback orders, stale replies, hook errors, action barriers, teardown, and malformed mode replies. Independently ran all 14 `input_bridge_order_spec.lua` checks under installed nightly; they passed. Real-provider tests exercise original-selection Cmd-C, Cmd-X, and Cmd-V through the actual adapter. CI pins the real public VSVim provider and an explicitly invalid VSVIM_SOURCE fails instead of silently skipping it.

The parent reports 20,729 adapter checks, 21 selection checks, and 5 full-setup checks passing; those full runs were not repeated in this read-only pass. Native preview keyboard verification remains in progress and is not claimed complete here.

No production/test edits; existing preview processes untouched.
