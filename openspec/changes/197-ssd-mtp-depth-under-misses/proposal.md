# Proposal

## Why

The MTP cycle drafts one token, or two when a rolling window of first-draft
acceptances is perfect (`qwen4_spec_depth` in `ds4.c`). The thresholds were
set on resident decode, where a third verify row costs little GPU time and
the second draft, accepted about 60% of the time on prose, "does not cover
the wider cycle".

Under SSD streaming at the owner's footprints the cost of a pass is
different. A pass stops at every layer whatever its row count (`191`), and
a row adds read waits only for the experts it routes that the other rows
and the cache do not have. A large fixed cost per pass favours deeper
passes at a lower acceptance than the resident thresholds allow. The gain
seen so far does not show it yet: in `190`'s step 0 at 40% of the experts,
MTP decode on code ran at 30.0 tokens/s against 22.9 plain (+31%, 1.93
tokens per pass), about the resident gain on code (+35%). So this is a
measurement first: whether depth 3 at lower acceptance, or a rule that sees
the pass's cost, beats the resident rule under streaming.

The verified output does not depend on the depth: greedy decoding emits the
target's argmax at every position, and exact sampling keeps its
distribution at any depth. Only the speed changes.

## What Changes

- **Step 0.** At 48, 54 and 60 GiB in `190`'s bench, MTP code, prose and
  copy kinds: forced depth 2 (`DS4_QWEN4_MTP_DEPTH=2`), forced depth 3, and
  the default policy; tokens per pass, the share of passes at depth 3,
  per-depth pass time and miss layers. Close if neither forced depth beats
  the default on any kind (pooled CI above zero) at 54 GiB.
- **S1.** A streaming-aware depth rule chosen from the table: the same
  acceptance window with thresholds that depend on whether the session
  streams, or the window combined with the pass's measured cost. The
  resident path keeps its current rule unchanged.

## Impact

- `ds4.c` (`qwen4_spec_depth` and the session fields it reads),
  `docs/SSD_STREAMING.md` (MTP under streaming).
- Starts after `190`; measured against what of `191` and `194` has landed,
  since both change a pass's cost.
