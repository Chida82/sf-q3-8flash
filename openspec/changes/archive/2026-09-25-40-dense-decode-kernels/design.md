# Design

## Context

See proposal.md for the motivation and the step list. The change has no spec
delta (`skip_specs: true`): each step must leave every output bit-identical,
which the harness checks.

State of the child that shapes the port:

- **Q8 decode path.** A decode token's Q8 projections take
  `ds4_gpu_qwen4_matmul_q8_0_tensor` -> `ds4_gpu_matmul_q8_0_legacy_tensor`.
  For `n_tok == 1` and no decode MPP, that dispatches
  `kernel_mul_mv_q8_0_f32` with `ds4_gpu_make_q8_0_mv_dispatch()`: NSG 4
  (2 under TP2), 2 rows per threadgroup, 8 SIMD groups above 65536 output rows.
  So `9bff1ca`'s `nsg == 4` condition holds on M5. Fused K/V/IQ/IK projections
  (T <= 2) and multi-row decode batches use other kernels and are not affected.
- **HC gate-mix path.** `ds4_gpu_qwen4_hc_gate_mix_tensor` uses the pair
  kernels for two tokens, which already share the activated inputs in
  threadgroup memory. For other token counts it uses the register-prefetch F16
  kernel (`QWEN4_K_HC_GATE_MIX_F16_PF`), the M5 default. The child already has
  the HC *norm* reuse kernels. It does not have `cdfc0d5`'s
  `kernel_qwen4_hc_gate_mix_f16_reuse`.
- **Trial port** on a scratch clone:
  - `a50fecc`, `04c0867` and `9bff1ca` conflict only in the Makefile, the
    `.gitignore`, and code the child no longer has: the removed
    `ds4_gpu_matmul_q8_0_decode_mpp_model_view_tensor`, and the M1-reuse test
    scaffolding in `tests/test_qwen4_kernels.c` main;
  - the build is clean and `make test-qwen4-kernels` passes;
  - on this M5 Max, `test_metal_q8_reduction` passes (3072 cases), and so does
    `test_metal_q8_gemv_reference` (1024 fixtures, 571,136 values, 0 bit
    differences, two- and four-row, default and safe math, NSG 1/2/4/8).
- **Tools**, used and not modified: `speed-bench/ab_bench.py` (A/A noise floor
  on the plateau: plain decode ±1-2% per pair, MTP decode ±1-2%, tokens per
  cycle exact) and StarForge `tools/parity-check.sh`.

## Goals / Non-Goals

**Goals:**
- Faster single-token decode on M5, with every logit bit-identical.
- Each step measured on its own against the previous step, and kept only on a
  measured gain.
- The ported code reviewed and refined as the project rule requires.

**Non-Goals:**
- Prefill kernels (`60-q4-expert-prefill`) and expert kernels (`50`, `70`).
- `bbbc012`'s M1 Max prefill HC-down tile.
- The generic HC rewrite of `028b43f`, and its M6 gate.
- Other devices: every gate this change adds names M5 (or keeps M1 Max as
  upstream has it), and the other devices keep their current kernels.

## Decisions

### D1. Port form, snapshots, commits

As in `30-mtp-cycle` (its design D1/D3):

- **Port.** `git cherry-pick -n` on `perf/40-dense-decode-kernels`.
- **Snapshots.** A tree snapshot per kept step (`git add -A -- .
  ':!openspec'`, `git write-tree`). A for the next step is a detached worktree
  `../sf-q3-8flash-prev` restored to the previous snapshot.
- **Commits.** Replayed as signed commits only at the user's request, with the
  upstream author and a `cherry picked from` line on the ported steps.
  `a50fecc` and `04c0867` become one commit: the second repairs the first, and
  the first alone changes rounding.
- **Frame.** Two commits of the child's own: the refinement commit and the
  closing docs/registry/record commit.

### D2. Hand-ported sites

From the trial port:

| Step | Site | Resolution |
|---|---|---|
| 1, 2 | `Makefile`, `.gitignore` | keep the child's files. Add targets `test-metal-q8-reduction` and `test-metal-q8-gemv-reference` (the latter built with `$(filter-out -ffast-math,$(OBJCFLAGS))`, as the PR does), their `clean` lines and ignore entries, in the child's help/target layout |
| 2 | `ds4_metal.m`, the new `qwen_rows4` argument | the child has no `..._decode_mpp_model_view_tensor`; drop the PR's hunk for it |
| 2 | the device gate | the PR's `ds4_gpu_device_name_contains("M1 Max")` becomes `... "M1 Max") \|\| ds4_gpu_device_is_m5_apple_silicon()`, the same M5 predicate the HC `_PF` default uses |
| 2 | `tests/test_qwen4_kernels.c` | `test_qwen4_q8_decode_rows` applies. Its call and the `DS4_TEST_QWEN4_Q8_ROWS_ONLY` focus path sit in the M1-reuse scaffolding the child does not have: call it from the child's `main` next to the other Q8 checks, without the focus env |
| 3 | `metal/qwen4.metal`, `ds4_metal.m` | take `kernel_qwen4_hc_gate_mix_f16_reuse` from `cdfc0d5` with its F16 loop pinned like `028b43f`'s (`fp reassociate(off)`, `contract(off)`, `x = l*(1/hc); u = (x*w)*sigmoid(x)`). Select it for a single token when the weights are F16 and the rank is 320, on M5, and only if D4's A/B shows a gain. `DS4_QWEN4_HC_MIX_PREFETCH` keeps forcing either existing kernel |
| 3 | `tests/test_qwen4_kernels.c` | a byte-exact case of the reuse kernel against `..._F16` and `..._F16_PF` at the production shape (E 2560, hc 4, rank 320, T 1) and at a small shape, next to the existing HC prefetch check. `cdfc0d5`'s M1 benchmark scaffolding is not taken |

### D3. Correctness

Every step:

- `make -j8` with no warnings;
- `make test -j8`, reading the suite names (AGENTS.md rule 19);
- `make test-qwen4-kernels`;
- the two Metal oracles once they exist (from step 1);
- the harness with `--bitwise` on all kinds: identical logits imply identical
  drafts, so the MTP kinds' decode dumps must match too.

At the end:

- `make test-qwen4-q2`;
- `python3 tests/test_qwen4_mtp_limits.py`;
- the StarForge parity oracle.

The Q2 pack uses Q8 dense projections too, and upstream's M1 validation was on
Q2. This change's gates run on Q4, which carries the same dense tensors.

### D4. Measurement and keep rule

- **Every step.** `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise`, all
  kinds (plain decode is the target; MTP draft passes use single-row Q8 too).
- **Keep rule.** As in `30-mtp-cycle` D5: plain decode above 1 by more than its
  noise floor, and no throughput metric below 1 by more than its floor.
  - Step 1 is also kept when neutral: `9bff1ca` is written on its reduction
    helper, and the change is bit-identical and removes a barrier.
  - An inconclusive result is repeated once with `--budget 600 --kinds plain`.
- **Step 3.** A/B's A is step 2's tree and B selects the reuse kernel on M5.
  `DS4_QWEN4_HC_MIX_PREFETCH` would force the same kernel in both trees, so
  the step's own gate is what differs.
- **Step 4** (optional, one line): the M5 default of 16 SIMD groups for the HC
  pair kernel, measured on the MTP kinds, where two-row verifies use it.
  Attempted only if steps 1-3 leave time in the session. Otherwise it is
  recorded as not attempted.

### D5. Review of the ported code

The project rule (`openspec/config.yaml`), in the form `30-mtp-cycle` D11 set:

- **Step review.** After each step builds and before its A/B. *Fix now*
  findings are fixed in the step; *refine later* ones wait for the final pass.
- **Final pass.** Over the Q8 matvec family in `dense.metal` (both reduction
  helpers, the two- and four-row instantiations), the Q8 dispatch in
  `ds4_metal.m`, the HC gate-mix kernels and their selection, and the new
  tests. Points to settle:
  - whether `helper_mv_reduce_and_write` is still used by Q8 (other kernels
    keep it);
  - whether the four-row shape list should be derived rather than listed;
  - whether the oracles' 1,000 lines can shrink to what covers these kernels
    without losing the negative control;
  - whether the M1 Max gate should stay (upstream's) or give way to one gate.
- **Gate.** `--bitwise` against the last kept step, speed not below noise. The
  pass lands as its own commit.

### D6. Record, registry, docs

- **Performance record.** The closing A/B is `--a <worktree of the current
  main> --b .` for the speed of this change, plus the record row against the
  Segment 1 start commit `91f225a`, appended to `speed-bench/perf-record.md`.
- **Registry.** `docs/upstream-prs.md` lines for `a50fecc`, `04c0867`,
  `9bff1ca`, `cdfc0d5`, `bbbc012` and `028b43f` take their measured verdicts.
- **Docs.** `docs/METAL.md` gets one line per new device default, only where it
  already lists kernel defaults.

## Risks / Trade-offs

- [M5 bitwise rests on this compiler] → The oracles and the harness check it
  on this machine. A later Xcode or macOS can change code generation, as
  `04c0867` showed on M1. The oracles stay in the tree, so a later run catches
  it.
- [Four-row tiles read all four weight rows before the bounds check] → Only
  complete tiles are selected: every listed shape's row count is a multiple of
  4, which `test_qwen4_q8_decode_rows` covers together with the fallbacks.
- [The gain is small next to noise] → Plain decode noise is ±1-2% per pair.
  Step 2's expected +2-7% is measurable; steps 1 and 3 may not be, and they
  follow the neutral and inconclusive rules of D4.
- [Measurement time] → About five harness invocations (steps 1-3, the
  refinement, the closing pair), plus parity twice: about 1.5 h of machine
  time.
- [Sync] → `dense.metal` is shared with upstream. The Q8 hunks are taken as
  upstream wrote them, so if #1056 lands the merge is clean or one conflict.
