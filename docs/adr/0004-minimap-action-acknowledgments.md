# Acknowledge processed minimap navigation explicitly

A closed Neovim fold can map many requested source rows to the same viewport.
Matching returned tops leaves requests outstanding indefinitely; resetting on
all same-top states loses newer input because overlay states are unrelated.
A bounded inferred FIFO also stalls once all its entries are unmatched.

Use optional positive action IDs with a companion `grid-minimap-ack-v1`
capability and provider `acknowledge_actions` declaration. Only their conjunction
adds begin.action_ack. Legacy pairs retain existing v1 fields. New hosts send
connection-monotonic IDs only on opted-in documents. The provider forces a state
with the latest processed ID even when the viewport is unchanged; ordered
coalesced state acknowledges all preceding actions. Strict field, integer,
identity and revision validation remains.

The host stores requested top and sent/acknowledged IDs, removing the FIFO/cap.
Older acknowledgments retain newer intent; folded latest acknowledgments retain
unfulfilled source position without stalling further wheel input. Actual editor
input flushes pending minimap navigation before input and resets intent; passive
hover/focus/blur has no such side effect. Source changes/hide reset gestures but
retain the Surface connection counter so delayed IDs cannot alias new requests.

The first wheel flush is immediate; a frame latch coalesces following events.
The final preceding 1k trace had 2.118–2.168ms until flush, contributing to 33.867ms
p95 against the unchanged 33ms requirement. This change removes that concrete
avoidable delay; only a subsequent pinned run can establish acceptance.
