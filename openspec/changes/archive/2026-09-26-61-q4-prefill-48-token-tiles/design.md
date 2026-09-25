# Design

## Context

See proposal.md for the motivation and the probe figures.

What the work builds on:

- **The profiler (`DS4_QWEN4_TIMING=2`, ds4.c `qwen4_prof_cut`).**
  - After every prefill chunk with T > 8 it prints one standard-error line:
    `ds4: Qwen3.8 prefill stage GPU ms/chunk (pos=<p> T=<T> ok=<0|1>):`
    followed by `ple`, `hc_attn`, `gdn`, `attn`, `hc_ffn`, `moe`, `moe_mid`,
    `moe_down`, `head` and their times in ms with one decimal.
  - It prints the line from any frontend, the bench included.
  - A plain harness run prefills three chunks: pos 0 T 8192, pos 8192 T 512,
    and pos 8704 T 2048.
  - Decode passes print a mean every 50 passes. They are not used here.
- **The harness (`speed-bench/ab_bench.py`).**
  - It schedules A and B runs as ABBA quads after warm-up and preheat.
  - It keeps each run's standard error in `logs/`, judges GPU clocks from
    mactop, and flags a pair whose run fell below 90% of the median clock.
  - Its verdict leaves out flagged pairs. `samples.csv` carries the flag in
    `note`.
  - `child_env` drops inherited `DS4_*` variables; `--env` sets one for both
    builds.
  - Its tests are `tests/test_ab_bench.py`, run directly.
- **The pooling script** (`$SCR/c60/pool.py`, 30 lines, session scratch).
  - It computes the median of pair ratios and a bootstrap 95% CI over
    several output directories.
  - Since `60`'s review it skips the pairs the harness dropped.
- **The tiles after `60`.**
  - `kernel_qwen4_moe_mm_mid_nax_t<NR1, XT, COMP>` and `_down_nax_t` run on
    M5 as 64-token tiles with tails (function constant 905 = 64).
  - A remainder goes to the narrowest instance that holds it: 64 or 32, and
    for the half operands (`narrow`) also 16 or 8.
  - B staging uses `NB = ceil(NR1 * 4 / 128)` items per thread and a guard
    for NR1 < 32.
  - The kernel test asserts level 2 against level 1, and level 4 against
    level 3, byte for byte, at T 641, 75 and 161. At level 2 on M5 these
    shapes have remainders 1, 11, 16, 17, 33, 37 and 38.

## Goals / Non-Goals

**Goals:**
- A section-time verdict that resolves about 1% on the MoE sections, with
  the same schedule, gate and output layout as a throughput run.
- The 48-token tile, with every output bit-identical, kept or dropped by
  that verdict.

**Non-Goals:**
- Changing what a throughput run measures or prints.
- Decode section verdicts. The T <= 8 lines exist, but no step here needs
  them.
- Narrow tiles for the float or compensated levels.

## Decisions

### D1. Form of the work, landing

- Branch `perf/61-q4-prefill-48-token-tiles` from `main` once
  `60-q4-expert-prefill` has landed.
- Snapshots, `../sf-q3-8flash-prev` and `../sf-q3-8flash-start` (`91f225a`)
  as in `60`.
- S0 leaves the child's binaries unchanged. `../sf-q3-8flash-prev` therefore
  stays at `main`, and O9's step A/B is also its A/B against `main`.
- One signed commit on `main` when the user asks.

### D2. S0: section-time mode

- **Flag.** `--sections <groups>` takes the target groups as a comma list.
  - It sets `DS4_QWEN4_TIMING=2` for both builds, through the same path as
    `--env`.
  - It checks each name against the profiler's group list and exits 2 on an
    unknown name.
  - The default kinds become `plain`. `--kinds` still selects.
- **Parsing.** Each run's standard error yields one record per chunk line,
  keyed by (pos, T).
  - A run that lacks an expected chunk is a run failure. The expected set per
    kind follows from its frontiers and the bench's resume.
  - Lines with `ok=0` fail the run.
- **Metric.** Per chunk: `r = sum(target) / sum(all other groups)`. Per valid
  pair: `r_B / r_A`, and the whole-chunk ratio `total_B / total_A`.
  - The summary gives per shape: A/B median target ms, A/B median untouched ms,
    the median normalized ratio with a bootstrap 95% CI (10000 resamples,
    fixed seed, as the scratch script), and the median whole-chunk ratio.
  - It is the same statistic `openspec/config.yaml` names.
- **Output.**
  - `sections.csv` holds one row per timed run and chunk: build, kind, pos,
    T, every group, the note.
  - The summary gains the sections table, and its correctness line is
    unchanged.
  - Profiled runs print no throughput table and no record row, since their
    tokens/s include the profiler's waits.
- **Pooling.** The scratch script moves to `speed-bench/ab_pool.py`.
  - It reads `samples.csv` (throughput metric, or `--prefill <frontier>`) or
    `sections.csv` (`--sections <shape>`, with the target groups given
    again).
  - It keeps the ABBA order check and leaves out flagged pairs.
- **Tests** in `tests/test_ab_bench.py`:
  - chunk-line parsing;
  - a missing chunk as a run failure;
  - an unknown group refused;
  - the normalized ratio cancelling a uniform clock change;
  - a flagged pair left out of both the verdict and the pool.
- **Validation with the model.**
  - (a) A/A: `../sf-q3-8flash-prev` against itself, plain, `--budget 600`.
    Every shape's CI contains 1, and its half-width is recorded as the
    noise floor.
  - (b) Known effect: `../sf-q3-8flash-base` at `60`'s S0 tree (its profiler
    cuts, none of its kernel steps; `53dcad6` itself cannot serve, since its
    tiled path has no `moe_mid`/`moe_down` cuts) against `../sf-q3-8flash-prev`. `60`'s steps cut routed MoE
    time by about 10% at 2053 tokens, so every shape's CI lies below 1.
- **Rejected alternatives.**
  - A separate script beside the harness. It would repeat the preflight,
    schedule, clock judging and gate.
  - Reading times from the CLI as `60` did. The CLI never splits prompts into
    the harness's chunks.
  - The whole-chunk GPU time as the metric. It carries the clock drift that
    the normalization removes (`60`: +0.8..+2.2% between trees in untouched
    sections).

### D3. O9: the 48-token tile

- **Instances.** `kernel_qwen4_moe_mm_mid_nax48` and
  `kernel_qwen4_moe_mm_down_nax48` = `<48, half, false>`, two enum entries
  inside the specialized range after `DOWN_NAX8`, and two names.
- **Remainder rule** (both kernels): `remainder > 48 ? 64 : remainder > 32 ?
  (narrow ? 48 : 64) : !narrow || remainder > 16 ? 32 : remainder > 8 ? 16 :
  8`. The float and compensated instances keep 32/64.
- **Staging guard.** `if (tid + b * 128 >= NR1 * 4) break;` replaces the
  NR1 < 32 guard. It folds to nothing at 32 and 64 and covers 8, 16 and 48
  (NB 2, second item for tid < 64).
- **Host.** One more dispatch in the narrow tail chain of each matrix, with
  12288 bytes of threadgroup memory for both matrices.
  - The 48-token C tile is 12 KB. Staging is 11 KB (mid) and 7 KB (down).
- **Probe first.** Compile both instances before anything else. If
  `matmul2d(48, 64, 32)` is rejected, or the test's level-2-against-level-1
  check fails, O9 is dropped with that reason and nothing else is built.
- **Test.** Add T 119 (counts 119/60/59, remainders 55/60/59: the 64-token
  tile at the top of its band). T 75 (38/37) and T 161 (33) then reach the
  48-token tile, and the call-site comment names each shape's tiles.
- **Rejected alternatives.**
  - Splitting 33..48 into 32 + 16 tiles. That is two passes, so the weights
    are dequantized twice: about 356 ms against 235 per expert set at 64
    columns.
  - A 48-token tile for every level. The float and compensated levels are
    env-only accuracy options.

### D4. Verdicts

- **S0**, a tool step: the child's binaries are unchanged. It is kept when
  the validation (a) and (b) pass and the unit tests pass.
- **O9:**
  - First, the section-time A/B `--sections moe_mid,moe_down --kinds plain
    --budget 600 --bitwise` against `../sf-q3-8flash-prev`. Kept when the
    normalized ratio's CI lies below 1 at one shape and above 1 at none
    (`openspec/config.yaml`). Inconclusive: one repeat, pooled with
    `ab_pool.py`.
  - Then the throughput harness once, `--bitwise`, all kinds, as the guard:
    PASS, and no metric's CI wholly below 0 (`ab_pool.py`).
- **The refinement** is measured the same way.

### D5. Correctness per step

- `make -j8` with no warnings.
- `make test -j8`, reading the suite names.
- `make test-qwen4-kernels`, with its byte-exact tile-width lines for every
  T.
- `make test-qwen4-q2`.
- `python3 tests/test_ab_bench.py`.
- At the start and the end: the parity oracle. At the end:
  `tests/test_qwen4_mtp_limits.py`.

### D6. Review

- After each step, a step review: *fix now* or *refine later*.
- Then a final pass over:
  - the sections code and `ab_pool.py`;
  - the two kernels' remainder rule and staging guard;
  - the host tail chain;
  - the test change.
- Question to settle: whether the per-width host dispatches (now 32, 16, 8,
  48) should become one loop over a width table.

### D7. Record, registry, docs

- `speed-bench/README.md`: a "Section-time mode" paragraph and `ab_pool.py`.
- `docs/upstream-prs.md`: the `496b153` line gains O9's outcome.
- The closing throughput A/B against `main` and the record row against
  `91f225a` go into Segment 1, as the project rule requires. If O9 is kept,
  its section-time figures go in the row's commit message.

## Risks / Trade-offs

- [`matmul2d` rejects M = 48, or its bits differ from the other widths] → the
  probe in D3 runs before anything else, and the test asserts it.
- [A 48-wide pass costs as much as a 64-wide one: the tensor unit works in
  32-column blocks] → the verdict shows a ratio near 1, and O9 is dropped.
  The tool from S0 remains.
- [The profiler's cuts serialize the sections, so overlap between kernels is
  invisible] → O9 is kernel-internal. The rule keeps overlap and scheduling
  steps on the harness.
- [Profiled runs are slower, so fewer pairs fit in a budget] → plain only by
  default, `--budget 600`, and one repeat when inconclusive.
- [The normalization assumes the untouched groups do not change] → the
  summary also prints the untouched medians and the whole-chunk ratio, so a
  change outside the targets shows.
- [Sync] → `ab_bench.py` is child-only. The kernel edits sit in the region
  `60` already changed, beside #1056's.
- [Measurement time] → parity twice, two validation runs, O9's section and
  guard runs, the closing throughput and record runs: about 1.5 to 2 hours.
