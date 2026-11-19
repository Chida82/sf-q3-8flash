# Proposal

**Closed on 2026-11-19, not adopted.** S1 with the top 3 predicted experts
per row: at 54 GiB, capped, MTP code +1.99% [+1.08%, +2.77%], MTP prose
-2.57% [-5.67%, +0.96%], plain +0.75% [-0.87%, +3.13%]; 48 GiB MTP code
+4.73%, 60 GiB -1.36% (2 pairs each). Top 10 lost 3.5-4.6%: the CPU work of
issuing the reads delayed the next batch, and about 15,000 wasted reads per
512-token run raised misses from 46k to 61k. Kept by D4's letter, not landed
by the owner's decision: a mixed result for about 300 lines on the hot path.
A retry needs more pairs per size and a reason the prose loss goes away.
Code: `6671e3e` (the branch was deleted). Figures: tasks.md.

## Why

`185` S2 found a predictor of the next layer's experts that passes: the
next layer's router applied to this layer's FFN input names 32-38% of the
misses with fewer wasted reads than saved ones (design D5 of `185`). It was
not built, because its cheapest probe lost: in the emulated 48 GB condition
a missed expert came back from 25 GiB of file cache at memory speed, so an
early read had little to hide and the wasted ones competed with real ones.

That reason does not hold in the condition the owner develops for (`190`):
the rest of the RAM is taken and a miss is an SSD read. In `190`'s step 0,
at 40% of the experts (about the 54 GiB footprint), a load waited 1.04 ms
on average, a third to a half of the layer calls missed, and decode ran at
23 tokens/s plain on code, 43 ms a token: tens of milliseconds of each token
are read waits with the GPU idle. sf-ds4-1flash closed its prefetch (`170`)
on a CPU guess that cost 0.7% of decode and needed 8 GB/s of wasted reads;
here the guess is one small matrix product on the GPU and the drive is far
from its bandwidth (one expert, 2.59 MiB, in about 1 ms).

`185` also explains what an early read must achieve: a layer waits for the
slowest of its reads, so it gains only when every one of its misses was
read early. Step 0 therefore measures whole miss layers covered, not misses.

## What Changes

- **Step 0, offline from a trace.** At 54 GiB, plain and MTP, code and
  prose: per miss layer call, whether the predictor's top 6 and top 10 named
  all its misses; the read wait those calls paid; the wasted reads. Close if
  the hidden wait projects to less than 3% of decode.
- **S1.** The next layer's router (logits and top-k only) runs on the GPU in
  the same command buffer as this layer's router, on this layer's FFN input.
  When the CPU reads this layer's ids it also reads the prediction and
  starts reading the predicted experts the cache lacks into free or
  evictable slots, while this layer's expert pass runs. The next layer then
  routes on its real input as today: a predicted expert it selects is a hit,
  one it does not select stays cached as an ordinary entry (or is the first
  victim, D3).
- Kill switch for the A/B; kept or dropped by `190`'s bench.

Output does not change: prediction only decides what is read early; every
layer still routes and computes on its own input.

## Impact

- `ds4_metal.m` (the streamed MoE call, the read pool, victim choice for
  early reads), `ds4.c` (the predictor's encode in the Qwen decode step),
  `metal/qwen4.metal` only if no existing router kernel fits,
  `tests/test_qwen4_ssd_experts.c`, `docs/SSD_STREAMING.md`.
- Starts after `190` and `191` S0: `191` changes when the CPU sees the ids,
  which is when early reads can start.
