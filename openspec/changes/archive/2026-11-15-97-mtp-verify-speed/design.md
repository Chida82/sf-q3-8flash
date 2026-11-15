# Design

## Context

The proposal rested on the 2026-11-14 measurement (tasks.md 1.1): verify
passes slower after the sync in `moe_down` (+21%) and `attn` (+7%), and B
getting half as many 3-token cycles. `95` recovered the `moe_down` part.
This change re-measured on current `main` before porting anything.

## Findings

**The 2026-11-14 A side was a mixed build.** `ds4_metal.m` reads the Metal
sources from `metal/*.metal` relative to the working directory. The queue that
produced the verify-row numbers ran the 765e9a5 binaries from the main
checkout, so A ran 765e9a5's host code on 062d4c3's kernels. That build
generates a different greedy text on the code prompt ("0, 0, 0, ..." runs),
which drafts well at depth 3: k1/k2/k3 = 6/161/104. Running 765e9a5 from its
own tree, with the same prompt, gives the same tokens as `main`, the same
draft at every cycle, the same accept/reject sequence
(`DS4_QWEN4_SPEC_TRACE=1` logs identical) and k1/k2/k3 = 32/229/50 on both.
Running the 765e9a5 binary from a copy of 062d4c3's `metal/` reproduces
6/161/104 exactly. Prose: 179/226/3 on both. The predictor's output did not
change, and neither did the acceptance. `ab_bench.py` runs every bench with
`cwd` set to its tree, so its results are not affected.

**#1238's attention already reaches the verify rows.** Verify rows run the
batched-session rows kernels (`82`): `kernel_qwen4_attn_decode_rows` calls
the same `qwen4_attn_decode_tile` (NSG 6 / HPS 2, `f768d14`) as T = 1, and
`kernel_qwen4_attn_merge_rows` the same `qwen4_attn_merge_wide_head`
(16-wide maxima, `6605c3c`). Sending each verify row through the single-row
core instead (one score/select/expand/decode/merge set per row) made verify
`attn` 11% slower at T = 2 and 21% slower at T = 3: the rows kernels already
cost less per row than separate dispatches. Dropped.

**Where a verify pass goes (Q4, current main).** A T = 2 pass costs 1.08-1.14x
a T = 1 pass at the same context, T = 3 1.38x. The second row's extra GPU time
is in `moe_mid` (+1350..1720 us), `moe_down` (+590..750 us) and `attn`
(+200..300 us); every other group is within the clock noise. The MoE extra is
the second row's own experts. On Q4 both expert passes already run the T = 1
kernels at verify sizes (Q4_K mid NR1 / NSG 4; MXFP4 down NR2 from `95`).

**Q2 has one #1238 kernel the verify rows did not use.** On Q2, T = 1 folds
the Q2_K down rows and the weighted reduce (with the HC residual update) into
`kernel_qwen4_moe_down_reduce` (`4ed25e4`). Verify rows ran
`kernel_qwen4_moe_down` and then `kernel_qwen4_moe_reduce`, one more dispatch
and a round trip of the partials per layer, and their down cost per row was
about 0.97 of T = 1, against 0.70-0.75 on Q4.

## Decision

Give the fold a token index (grid y, per-token offsets of every operand; zero
at T = 1) and route the MTP verify rows (T = 2, 3 under the row-exact flag,
never deferred at T <= 3) through it on Q2_K down experts. Each row keeps
the single-token arithmetic. `tests/test_qwen4_kernels.c` pins the fold
byte-exact against the verify dispatch (down, then reduce), output and
residual, at T = 1, 2, 3 on the model shape; until now the fold had no pin
in the suite at all.

`ab_bench.py --sections` now reports `verify T=<n>` shapes for the MTP kinds
and lengthens their generation to 640 tokens, so the verify passes reach the
profiler's 50-pass lines.

## Risks

- The fold now runs on verify rows only on the Q2 pack. Q4 (MXFP4 down) takes
  the same path as before. Its byte-identity rests on the new pin and the
  identity test.
- On Q2, `--sections` reports verify down time under `moe` (as for T = 1), so a
  section A/B across this change must target `moe,moe_down` together.
