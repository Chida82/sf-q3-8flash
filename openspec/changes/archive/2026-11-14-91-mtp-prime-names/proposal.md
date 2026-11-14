# Proposal

## Why

The child and upstream both have fields named `mtp_tail_valid` and
`mtp_tail_pos` on the Qwen graph, with different meanings:

- upstream (`92f57fc`, `cd1c550`): the predictor's state is current through
  `mtp_pos`; the flag stays set while decoding and several predicates read it;
- the child (`30`, priming): one primed prompt row waits in `mtp_tail` for the
  token that follows it; `qwen4_graph_mtp_tail_flush` runs it and clears the
  flag at the first decode.

At the sync to `b3f5018` (`90`) the merge took two upstream predicates that
read upstream's meaning. Both compiled. One made every MTP cycle replay the
whole context: MTP output left plain output at word 21, at 4.7 t/s against
59 (`90` merge-log, "Post-merge fix"). The identity gate caught it; nothing
earlier could, because the code was valid C with the wrong meaning.

Upstream adds and changes code that reads these fields at almost every sync
(19 `mtp_tail_valid` sites at `b3f5018`). The next one will meet the same trap.

## What Changes

Rename the child's fields and function so upstream code that reads upstream's
meaning stops compiling (AGENTS.md rule 18: remove the failure mode, do not
document it):

| Today | After |
|---|---|
| `mtp_tail` (tensor) | `mtp_prime_row` |
| `mtp_tail_pos` | `mtp_prime_pos` |
| `mtp_tail_valid` | `mtp_prime_pending` |
| `qwen4_graph_mtp_tail_flush` | `qwen4_graph_mtp_prime_flush` |

Each `sf-keep(mtp)` marker that `90` placed at a replaced upstream predicate
names the new field. The comment on `qwen4_graph_mtp_prime` describes the
pending row with the new names.

Non-goals: no change to behaviour, output or speed.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: a rename)

## Impact

- `ds4.c` only (graph struct, priming, flush, reset, snapshot load, the two
  predicates `90` fixed).
- Sync cost: none new. The child already carries these lines as its own;
  upstream's `mtp_tail_*` sites are removed with `sf-ablate(mtp)` markers.
- Depends on `90`.
