# Proposal

## Why

Qwen3.8 refuses `--ssd-streaming` when the engine opens: the check is in `ds4.c`
near the `"ds4: Qwen3.8 requires Metal ..."` message. Today only the BF16
n-gram table is read from disk. So Q4 needs 69.7 GiB resident and Q2 about
41.7 GiB, and a Mac under 50 GB cannot run Qwen at all. The upstream PR #1056
(open) adds routed-expert streaming for Qwen. This change ports it: the child
then runs on 32-48 GB machines, with output identical to a resident run.

There is a second reason to do this now. The generic DeepSeek streaming
machinery is still in the child: `stream_expert_cache` has 795 references in
`ds4_metal.m` and `ssd_streaming` has 173 in `ds4.c`. It looks like an
ablation candidate. But `e37f185`, the PR's foundation commit, builds Qwen
streaming on it (`ds4_gpu_stream_expert_cache_*`: the entries, slot
addresses, prepare-selected-batch, pread notes and hotness). So most of it is
not dead: the port decides what stays, and removing it first would have to be
undone.

## What is known

- **The PR moved.** Its head was `b1af94b` in `docs/upstream-prs.md` and is now
  `4642526`, three commits later:
  - `81ee4ba`: sizes the Qwen expert cache from the smaller of 87.5% of RAM
    and Metal's recommended working set, without discounting twice.
    SSD-specific, so it is in scope.
  - `089d966`: a `DS4_QWEN4_MTP_PREFILL` policy that skips predictor history.
    It changes the draft context and can lower acceptance. This is MTP work,
    out of scope; it goes in the registry for a later MTP change.
  - `4642526`: Q4 decode loads, M1 Max prefetch, and SSD parity tests. The
    SSD tests are in scope. The Q4 decode part overlaps what `50` and `70`
    took, and goes in the registry for a later Q4 change.
- **Commits routed here** (all by the #1056 author, sizes from `git show --stat`):

  | Commit | What it does | Size | Author's claim (M1 Max 32 GB) |
  |---|---|---|---|
  | `e37f185` | a bounded (layer, expert) slot cache in owned `MTLBuffer`s, filled by `pread`. Routed kernels read per-expert GPU addresses through function constant 906 (`qwen4_expert_addresses`), so their arithmetic is unchanged. Only routed experts stream: 63.40 GiB of the Q4 file, while 6.32 GiB stays mapped. It adds memory admission, `test_qwen4_memory` and `test_qwen4_ssd_experts`. | 10 files, +1001/−83 | output identical |
  | `81ee4ba` | the memory budget fix above | 3 files, +53/−14 | 22.96 GiB planned at ctx 32768 on 32 GiB |
  | `e2b4a47` | eviction planned once per batch with a bounded heap | 4 files, +427/−2 | scan time −81/−86% |
  | `9e1429b` | MTP staging bounded from compact sizes, freeing cache slots | 2 files, +113/−15 | 7371 → 8212 slots |
  | `d6cbc77` + `81b9ebb` | expert reads overlapped with cached gate/up, MoE down and MTP verify | +316/−24, +186/−94 | decode +23-31% with MTP |
  | `5cbdb6e` (SSD part) | a two-stage streamed prefill pipeline | +424/−63 | prefill +6-11% |
  | `2ba92ab` + `fd0c24a` | a streamed prefill grid over active experts only, and its tests | +418/−15, +120/−26 | — |
  | `47ca2eb` | removes the M1 Max gate from the prefill overlap | +14/−24 | — |
  | `85d37ae` | Q2 only: stages the selected experts of the Q4-typed MTP layer instead of the whole layer | +209/−12 | Q2 MTP 4.55 → 7.86 t/s |
  | `4642526` (SSD tests) | Q4 SSD coverage at 32/33 and 128 tokens, addressed against resident kernels | — | decode 6.07 → 6.42 t/s |

- **The child's kernels diverged from the PR's base.** `50`-`70` added or
  rewrote the M5 decode and prefill kernels: `_pf`, `qwen4_moe_shared_q8_mid`,
  `qwen4_moe_shared_q8_rows`, `kernel_qwen4_moe_mid_iq2`,
  `kernel_qwen4_moe_down_q2k`, and the tensor tiles with their tails. The
  address-table path of `e37f185` must reach each of them. This is the
  largest source of risk and conflict.
- **The refusal text is upstream text** (the reasoning of StarForge rule 4
  for the steering refusal).
  The port takes the PR's wording for the lifted check. If upstream merges
  #1056, the sync then brings the same text and does not conflict.
- **This machine** is an M5 Max with 128 GiB. Smaller Macs are emulated with
  `sf-q3-8flash-bench --simulate-used-memory <GiB>`, which exists in the
  child: 80 GiB locked approximates a 48 GB machine. The harness cannot pass
  bench arguments today.
- **Expected minimum RAM** [inferred from the PR]: about 10 GiB (Q2) or 12
  GiB (Q4), plus the expert cache. On 32-48 GB, about 20-45% of the Q4
  experts fit.

## What Changes

In this order, from `main`:

1. **Intake.** Registry lines in `docs/upstream-prs.md` for `81ee4ba`,
   `089d966` and `4642526`, with the new head `4642526`. Mark the
   streaming and expert-cache code that `e37f185` calls with `sf-keep`
   (reason, and revisit when this change lands).
2. **S0, tool: bench arguments in the A/B harness.**
   - `--bench-arg ARG` (repeatable) passes ARG to both builds' bench.
   - `--b-bench-arg ARG` passes ARG to B only, so A can be resident and B
     streaming from the same tree. The correctness gate then proves that the
     streamed output is identical.
   - The record row is suppressed when any bench argument is given.
3. **A, the foundation.** Port `e37f185` and `81ee4ba`, and extend the
   address tables to the child's own M5 kernels. Lift the refusal for
   `ssd_streaming` only, keeping TP, pipeline and power throttling refused.
   Port the two test programs.
   - **Gate 1:** resident output is bitwise identical to `main`.
   - **Gate 2:** resident speed does not regress on the harness.
   - **Gate 3:** streamed output is token-identical to resident for both
     packs, at 128 GiB and under `--simulate-used-memory` emulating 48 GB
     and 40 GB (the smallest this 128 GiB host can emulate under its kernel
     wire limit).
4. **B, overlap and I/O**, one measured step each, all on streamed runs at a
   48 GB emulation:
   - `e2b4a47`;
   - `9e1429b`;
   - `d6cbc77` + `81b9ebb`;
   - the SSD part of `5cbdb6e`;
   - `2ba92ab` + `fd0c24a`;
   - `47ca2eb`;
   - `85d37ae`, Q2;
   - the SSD tests of `4642526`.

   A step is kept when its streamed target metric's pooled CI lies above
   zero, no streamed metric lies wholly below zero, and the resident path
   stays bitwise identical and within noise.
5. **Docs:**
   - the `AGENTS.md` product contract and the misleading-name traps (engine
     open no longer rejects SSD streaming for Qwen);
   - `docs/SSD_STREAMING.md` and `docs/QWEN38_FLASH_NEXT.md`, with the
     memory policy and the minimum RAM measured under emulation.

Not in scope:
- `089d966` and the Q4 decode part of `4642526`;
- popularity preloading and `--ssd-streaming-full-layers`, which the PR
  does not support for Qwen either;
- streaming the dense or shared weights;
- removing unreachable DeepSeek streaming code. That is a separate
  ablation after this change, which will know exactly what is reachable.

## Capabilities

### New Capabilities
- `ssd-streaming`: routed-expert streaming for Qwen on Metal. Output is
  identical to the resident run. The resident path does not regress. Memory
  admission refuses with a clear message. The mode is documented with its
  minimum RAM.

### Modified Capabilities
- `perf-harness`: bench arguments for both builds or for B only.

## Impact

- `ds4.c`: engine-open check, memory admission, Qwen streaming state.
- `ds4_metal.m`: stream expert cache, Qwen bind and address paths.
- `metal/qwen4.metal`: function constant 906 in the routed kernels.
- `ds4_gpu.h`.
- New tests `tests/test_qwen4_memory.c` and `tests/test_qwen4_ssd_experts.c`,
  their Makefile targets, and `tests/test_qwen4_ngram_state.c`.
- `speed-bench/ab_bench.py`, `tests/test_ab_bench.py`,
  `speed-bench/README.md`.
- `AGENTS.md`, `docs/SSD_STREAMING.md`, `docs/QWEN38_FLASH_NEXT.md`,
  `docs/upstream-prs.md`, `speed-bench/perf-record.md`.
- About 3000 lines ported, the largest change in the plan. At every later
  sync, `qwen4.metal` and the Qwen bind path will conflict until upstream
  merges #1056.
