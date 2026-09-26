# Proposal

## Why

`70-q2-kernels-m5` measured the remainder tails for the Q2 pack on M5 (its step
Q1) three times and dropped them each time. The tails are bit-identical and make
Q2 prefill much faster: about +20% on a 512-token turn. But every campaign also
read one decode metric slightly below zero, and the project rule drops a step
when any throughput metric's pooled CI lies wholly below zero. The owner's
question is whether a +20% prefill gain is worth up to 1% of decode. This change
first finds out what that decode cost really is, then decides.

## What is known

**The code.** `qwen4_moe_mm_tails` in `ds4_metal.m` decides whether an expert's
remainder tokens (those that do not fill a 64-token tile) run in narrower
32/16/8-token tiles. On M5 it is on for Q4_K/MXFP4 (since `60`) and off for
IQ2_XXS (type 16) and Q2_K (type 10). Q1 adds `type == 16u || type == 10u` to
the M5 clause, which is a one-line change. `DS4_QWEN4_MOE_TAILS=1` already forces the
tails on at run time with no code change. The M3 Ultra clause already covers
16/10.

**Where the tails can run.** Only on the tiled path. `ds4.c` takes that path
only above `mm_min = 64` tokens. Decode and MTP verify (T at most 8) never
reach the tails, so no tail kernel runs during decode. The pipelines are
created lazily, on first use in each process. Each bench run is a fresh
process.

**Correctness.** The tails are byte-exact:
- `70` extended `test_moe_mm_tiles_iq2` with a level-2-against-level-1 check
  and the padded 640/768 Q2_K down at T 161 and 641;
- the tile hashes equal the pin from before the gate;
- every A/B ran with `--bitwise` and passed.

**GPU section time, Q2, on the tree of `70`'s step P1.** Routed MoE time
(`moe_mid` + `moe_down`, normalized by the untouched groups):

| Shape | Result | 95% CI |
|---|---|---|
| prefill 8192 | −6.4% | −6.7..−6.1 |
| prefill +512 | −24.8% | −26.7..−24.7 |
| prefill +2048 | −17.0% | −17.2..−16.0 |
| decode | −0.6% | −2.2..−0.2 |

The decode GPU time per pass is not slower. It reads slightly faster, on a
shape the tails cannot reach.

**End-to-end, Q2, bitwise, pooled medians and bootstrap 95% CIs.** Each column
is one campaign: on `70`'s P1 tree, on `70`'s final tree, and on the final tree
with the tails limited to batches under 4096 tokens.

| Metric | P1 tree | Final tree | Final, < 4096 only |
|---|---|---|---|
| prefill 8192 | +2.2% (+1.1..+3.8) | +2.4% (+1.8..+3.7) | +0.2% (−0.7..+1.4) |
| prefill +512 | +19.8% (+18.0..+61.7) | +20.8% (+19.1..+21.7) | +19.8% (+18.6..+22.5) |
| prefill +2048 | +6.3% (+6.2..+6.4) | +6.9% (+6.2..+7.8) | +8.1% (+5.6..+8.9) |
| MTP-code prefill 2048 | +10.0% (+9.1..+11.3) | +11.3% (+10.1..+13.5) | +7.9% (+1.0..+13.9) |
| MTP-prose prefill 2048 | +7.7% (+6.2..+9.4) | +5.5% (+2.6..+8.8) | +5.7% (+4.2..+10.7) |
| plain decode | +0.0% (−0.4..+1.0), n=5 | **−0.77% (−1.20..−0.47), n=20** | −1.11% (−1.94..+0.17), n=10 |
| MTP-code decode | **−0.53% (−0.78..−0.12), n=43** | +0.21% (−0.51..+0.74), n=48 | −0.35% (−1.42..+0.65), n=17 |
| MTP-prose decode | +0.1% (−0.5..+0.5), n=6 | −0.33% (−2.38..+3.13), n=6 | −0.32% (−0.74..+0.21), n=18 |

Two cells, in bold, lie wholly below zero. Both held after a repeat pooled in.
The decode metric that trips moves between campaigns. Over the nine decode
readings, the median is about −0.3%, with a range of +0.2% to −1.1%.

**Controls, all reading about 0.**
- Tails off in both builds (`--env DS4_QWEN4_MOE_TAILS=0`, same binaries as
  the P1-tree guard): MTP-code decode −0.05% (−0.34..+0.23), n=37. The loss
  follows the tails' behavior, not the binary.
- X1, the same binary as `main` on both sides, with A's prefill slowed by
  bitwise knobs (one tile per launch, prefill +4.2%): MTP-code decode −0.02%
  (−0.32..+0.26), n=42.
- X2, the same with tile-major order added (prefill +6.9%): MTP-code decode
  +0.18% (−0.49..+0.43), n=36.

**Ruled out.**
- A decode kernel: none of the tails runs in decode.
- Thermals: GPU clock, temperature and power were equal between A and B.
- A faster prefill as such: X1 and X2 read 0.
- The 8192-token chunk: the variant below 4096 tokens loses the same.
- The binary or its code layout: the control with tails off in both builds
  reads 0.

**Not yet tested.** Every decode loss above fits a fixed cost of about 10-15 ms
per decode phase better than a cost per token:

| Reading | Tokens in the phase | Fixed cost it implies |
|---|---|---|
| plain −0.77% | 64 per frontier, 3 frontiers | 10 ms per phase |
| MTP-code −0.53% | 128 | 12 ms |
| gated plain −1.11% | 64 per frontier | 15 ms |

The bench's steady decode leaves out only the first cycle. A stall of a few
milliseconds early in each decode phase therefore reads as a percentage that
shrinks as the phase gets longer. Candidates: work that Metal finishes
asynchronously after the lazy pipeline creation, a GPU clock ramp after a denser
prefill, or cache state left by the tail dispatches. A fixed cost per request
and a cost per token lead to different decisions.

**The trade in time per turn.** These figures are from the final-tree
campaign on Q2.

| Turn shape | Without tails | With tails | Saved |
|---|---|---|---|
| +512 prompt tokens on 8192 context | 780 ms | 640 ms | 140 ms |
| +2048 prompt tokens | 2246 ms | 2098 ms | 148 ms |
| 8192-token first chunk | 7049 ms | 6849 ms | 200 ms |
| MTP-code 2048 prompt tokens | 1954 ms | 1755 ms | 199 ms |

The break-even length is the decode length at which the decode cost equals
the prefill time saved.

| Decode cost | Per token | Break-even after +512 | After +2048 |
|---|---|---|---|
| −0.3% per token | 0.06 ms | 2260 tokens | 2390 |
| −0.77% per token | 0.16 ms | 880 tokens | 930 |
| −1.1% per token | 0.23 ms | 610 tokens | 650 |
| 10-15 ms per phase | fixed | never: the saving is 10× the cost | never |

Coding-agent turns on this child's server usually add hundreds to thousands of
prompt tokens and generate a few hundred. Under every reading above, the tails
win for such turns. They lose only for single turns that generate more than
about 600-2400 tokens, and only if the cost is per token.

**Q4 is not affected.** The Q4_K/MXFP4 pack has had its tails on M5 since `60`,
and Q1 does not touch its path.

## What Changes

In this order, from `main` with `70-q2-kernels-m5` landed:

1. **S0, tool: a decode-length override in the A/B harness.**
   `ab_bench.py --gen N` sets the tokens generated per frontier for every kind
   in place of the defaults of 64 and 128. The metric names stay the same. The
   summary header and the record row show the override. With `--gen 512`, a
   fixed cost of 10 ms per phase reads about −0.1% instead of −0.8%, while a
   cost per token keeps its size. Checked by unit tests and one A/A run.
2. **D1, diagnosis: fixed or per token.** The Q1 gate is applied as a probe,
   and the plain and MTP-code kinds run with the default length and with
   `--gen 512`, one after another. A per-token timing probe
   (`DS4_METAL_CB_TIMES=1`, or the bench's per-token times if present) shows
   where in the phase the extra time falls. Two cheap attributions follow:
   - the pipelines created ahead of time (a probe);
   - mid tails only against down tails only (a probe knob).

   No probe code lands.
3. **D2, the decision.** From D1, one of:
   - **(a) the cost is fixed per decode phase:** the tails land as the default
     on M5 for 16/10. A new clause in `openspec/config.yaml` defines when a
     fixed per-request cost may be traded against a measured saving. If D1
     found the source and it can be removed bit-identically, that fix lands
     too.
   - **(b) the cost is per token and a probe removes it:** the tails land with
     the fix, under the existing rule.
   - **(c) the cost is per token and nothing removes it:** the owner decides
     between the trade-off clause (the tails on by default, with the loss
     recorded) and the tails staying off, with `DS4_QWEN4_MOE_TAILS=1`
     documented as the prefill-first setting.
4. **Closing:** parity with Q2 and Q4, the MTP limits, an A/B against `main`
   and a record row for both packs, and the `496b153` line of the registry.

Not in scope:
- changing the tails for Q4_K/MXFP4 or for M3 Ultra;
- a new tile width, since `61` measured 48 tokens and dropped it;
- the SSD sparse-tile part of `496b153`, which belongs to `80`.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `perf-harness`: a generation-length override, so that a fixed per-phase cost
  can be told apart from a per-token cost.

## Impact

- `speed-bench/ab_bench.py`, `tests/test_ab_bench.py`, `speed-bench/README.md`.
- `ds4_metal.m`: `qwen4_moe_mm_tails`, a one-line gate, only under outcomes
  (a), (b), or (c) with the clause.
- `openspec/config.yaml`: the trade-off clause, only under (a), or under (c)
  with the owner's approval.
- `docs/upstream-prs.md` (`496b153` line), `speed-bench/perf-record.md`.
- No model format, API or output change: the tails are bit-identical.
