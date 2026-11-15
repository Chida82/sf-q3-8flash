# Design

## Context

`ce6d991` touches 6 files and about 500 lines. Its base is upstream `main`
before #1238 and before the #1056 merge. The child after `90` has #1238's
`b5aedb9` HC loads and keeps its own `30` priming and `82` exact verify rows,
which upstream lacks. The kernel arithmetic is the eager pair's; only where
and when R is written changes.

## Decisions

### D1. Bit-identity first, measured where it can fail

- **Kernel:** port the PR's byte-exact cases in `tests/test_qwen4_kernels.c`
  (R, xn and inj after the deferred path against eager combine + norm, f32,
  f16 and q8 inject weights, T = 3..256). Add one case with the child's M5
  reuse layout if the deferred kernel writes into it.
- **Graph:**
  - `ab_bench.py --bitwise` on every kind: plain prefill and decode logits;
    the MTP kinds cover priming;
  - `tests/test_qwen4_mtp_identity.py` at every depth, since priming reads
    the trunk R;
  - one streamed-against-resident run (`80`'s check), since SSD prefill runs
    the same HC path.
- **Steering:** one `--dir-steering-file` CLI run with an FFN scale, compared
  byte for byte with the same run on `main`. The steering flush path has no
  other gate.

### D2. The verdict is GPU time, then the harness as guard

The claimed end-to-end gain (+1.3..+2.4% prefill) sits at the harness's
resolution on prefill, a few percent. Under `openspec/config.yaml` the step is
therefore decided on GPU time:
- ABBA pairs of `DS4_QWEN4_TIMING=2` runs (`ab_bench.py --sections` with the
  HC/FFN groups as targets, pooled by `ab_pool.py`);
- kept when the ratio's CI lies below one at a prefill shape and above one at
  none.

The harness then runs once as the guard: bitwise output, no throughput
metric's pooled CI wholly below zero. The kept build gets a record row in the
current segment of `speed-bench/perf-record.md`.

### D3. Exceptions to the deferral follow the child's readers of R

Upstream's list of eager writes is:
- T <= 3;
- PLE-feeding layers;
- the last trunk layer;
- debug dumps;
- the steering flush.

The child adds one reader, `30`'s priming, which reads R after the last trunk
layer of every prompt chunk. Before porting, list every reader of `g->R` in
the prefill path of the synced tree (`rg -n 'g->R\b' ds4.c` within
`qwen4_graph_forward_tokens` and its callees). Each must either be on the
eager list or flush the pending write. The list goes in the step review.

## Risks / Trade-offs

- **A missed reader of R gives wrong logits only on the path it serves**
  (priming, steering, SSD). The gates in D1 cover each of them once. A reader
  that none of them reaches is found only by D3's list. That is why the list
  is written before the port, not after.
- **The gain is small and may not reproduce on this tree.** #1238 already
  reorders HC loads. If D2's ratio CI crosses one, the step is neutral. It
  is then kept only if it deletes more lines than it adds, which it does not
  (+500), so it is dropped and recorded.
- **`DS4_QWEN4_NO_HC_DEFER`** is a kill switch the child would carry. Keep it
  only while the change is measured; the final pass removes it unless a
  measurement needs it.
