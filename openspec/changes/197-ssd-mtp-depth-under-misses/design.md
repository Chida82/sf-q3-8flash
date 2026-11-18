# Design

## Decisions

### D1. Step 0

Forced depths need no code: the policy reads `DS4_QWEN4_MTP_DEPTH` per
cycle. `ab_bench.py` with `--env` on both sides compares forced against
default (A = default, B = forced, the same build), 8 pairs per kind at 54
GiB, then the winners at 48 and 60. The stream timing summary gives miss
layers; the bench prints tokens per cycle and per-depth cycle times (`k1`,
`k2`, `k3`).

### D2. S1

Candidates, simplest first:
1. The same window with a lower engage threshold under streaming (for
   example 6 of 8 first drafts accepted instead of 8 of 8), chosen from the
   acceptance rates step 0 records.
2. A cost rule: engage depth 3 when the measured time of a depth-3 pass
   divided by its expected tokens beats depth 2's, with the expectation from
   the window. Both times come from the passes just run.

### D3. Keep rule

`190`'s bench, capped and RAM taken, at 54 GiB then 48 and 60: kept when
decode of an MTP kind has a pooled CI above zero and no metric's CI lies
wholly below zero, the copy kind included (it drafts deep runs); tokens per
cycle reported. Resident MTP decode checked unchanged (`--bitwise`, same
rule path).

## Risks / Trade-offs

- A deeper pass routes more experts and may evict what the next pass needs;
  step 0's miss layers show it.
