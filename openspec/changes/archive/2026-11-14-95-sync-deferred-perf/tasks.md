# Tasks

Starts from `main` with `90` landed. Model runs are strictly sequential; each
step is judged against the previous one with `speed-bench/ab_bench.py`.

## 1. Embedding gather (the idea of 1c6d058, on qwen4_embd_at)

- [x] 1.1 Add `kernel_qwen4_embd_rows` to `metal/qwen4.metal` (ids, table, type, row bytes, E, hc, T; writes every HC stream) and its wrapper `ds4_gpu_qwen4_embd_rows_tensor` in `ds4_metal.m` / `ds4_gpu.h`.
- [x] 1.2 Kernel test in `make test-qwen4-kernels`: byte-exact against `qwen4_ref_row` plus the host HC copy, for F16, BF16, Q8_0 and Q4_0 tables, token ids at 0, the last row and random, `T` of 1, 127, 128 and 4096. (Passed: `embedding rows: f16/bf16/q8_0/q4_0 tables at T=1/127/128/4096 byte-exact in every HC stream`.)
- [x] 1.3 Device branch in `qwen4_graph_stage_embeddings` (no image spans, `T` at or above the threshold); replace the `sf-keep(sync)` marker. No GLM kernel or file comes back.
- [x] 1.4 Threshold: `ab_bench.py --bitwise` on prefill at 512, 8192 and the long-context frontiers with the threshold at 1, 32 and 128; keep the smallest that never loses. (2026-11-14. Threshold 128, plain kind: `PASS (tokens; bitwise)`, 11 pairs, prefill 8192 +0.25% (CI -4.97..+6.00), +512 +0.10%, +2048 +0.36%, decode +0.06%: no gain shown. Threshold 1: `FAIL: B differs from A: mtp-code, frontier 2048, token index 1`. Unproven lead: `g->selected` is shared with committed but unfinished MTP work, so the ids write can race it; a safe version needs its own ids buffer, carried wherever graphs share or copy fields (e.g. the `host_row` copy). 32 and 128 cannot be told apart by the benchmark kinds (no chunk between 32 and 127); `ab_bench.py` has no frontier option, so 16K/32K were not run.)
- [x] 1.5 Keep only if prefill gains and nothing loses; one perf-record row. (Dropped 2026-11-14 and reverted in full: no gain at 128, a token divergence at 1. Upstream's `sf-keep(sync)` marker in `qwen4_graph_stage_embeddings` stays. To retry: own ids buffer, the MTP kinds at every threshold, and a long-context frontier in `ab_bench.py` first.)

## 2. MTP last-row MoE

- [x] 2.1 Restore `qwen4_graph_moe_last` and call it from `qwen4_graph_mtp_steps` for the final predictor row. (Tried 2026-11-14 as `qwen4_graph_nextn_layer` calling `qwen4_graph_moe_impl(..., true)`: the predictor's MoE output is read only at its last row.)
- [x] 2.2 `python3 tests/test_qwen4_mtp_identity.py --model <Q4>`; A/B on the MTP kinds. Keep only on a gain. (Measured 2026-11-14: identity 36/36 SAME, A/B PASS (tokens; bitwise), 16 pairs, MTP decode +0.3% code (-0.4..+3.9%) and +0.1% prose (-0.3..+0.2%), tokens/cycle unchanged. Neutral on speed. Owner decision (2026-11-14): adopted anyway, as upstream's own `qwen4_graph_moe_last` text called from `qwen4_graph_nextn_layer`: it keeps `last_only` in use and the function identical to upstream, so the next sync has fewer conflicts; identity 36/36 again on the upstream form. Figures in `$SCR/gpu/ab-95s2-*`.)

## 3. The 70 MXFP4 down pass

2026-11-14 (97 step 1.1): on verify passes main's moe_down is 21-23% slower than 765e9a5 (T=2 and T=3, Q4), the largest single loss in an MTP cycle; this step comes before step 2.

- [x] 3.1 Port the child's `qwen4_moe_down_mxfp4_pass` and `qwen4_moe_shared_q8_rows` from `765e9a5` into `kernel_qwen4_moe_down_mxfp4_pf`; `make test-qwen4-metal-units` and the kernel suite byte-exact. (2026-11-14: no kernel code needed. Upstream's kernel already carries the paired-row path (function constant 907 `qwen4_mxfp4_pair_rows`, `qwen4_q8_pair_dot`), but the host enables it only on legacy devices, and NR defaults to 1. Host-only change in `ds4_metal.m`: `qwen4_moe_mv_rows(type, n_tokens)` defaults to NR2 for MXFP4 at T > 1 on M5 (env overrides still win; all three callers pass `n_tokens`), and `pair_rows` also holds on M5; `sf-keep(70)` marker. T = 1 and M6 keep upstream's NR1. `test_mxfp4_down_exact` mode 5 pins the default dispatch byte-exact against the unspecialized kernel at T = 1..3, odd shapes, every shared slot. Kernels, metal units (145 PASS), `test-qwen4-q2`, identity 36/36 all pass.)
- [x] 3.2 A/B on plain and MTP decode. Keep only on a gain. (Kept 2026-11-14: `PASS (tokens; bitwise)`, ab-2 24 pairs plus ab-3 14 plain pairs. MTP decode +2.94% code (CI +2.89..+3.08, every pair positive, A at the high mode 87.7 t/s) and +2.42% prose (+2.32..+2.49); tokens/cycle unchanged; plain decode -0.05%, prefill pooled over 22 pairs within ±0.05%. `DS4_QWEN4_TIMING=2`: verify moe_down -20.4% at T=2 and -22.6% at T=3, i.e. the loss 97 found is recovered; attention (+7%) is not addressed here. Figures in `$SCR/c95/`.)

## 4. dense.metal names

- [x] 4.1 Rename the child's `82` templates to `*_vrows*`; verify `MTP verify rows ... byte-exact vs single rows` in `make test-qwen4-kernels`. (2026-11-14: `kernel_mul_mv_q8_0_f32_rows(_impl)` and `kernel_mul_mv_t_t_4_rows(_impl)` of the child are now `*_vrows*`, host names unchanged; upstream's `mul_mv_t_t_4` typedef is shared and stays. Pin passes. Upstream's `kernel_mul_mv_f16_f32_4_rows(_bf16)` and `kernel_mul_mv_q8_0_f32_rows8` have no host caller here; left as upstream code.)
- [x] 4.2 Try upstream's exact F16 multi-row kernel for verify rows; keep it if the same pin passes, and delete the child's F16 r2/r3. (Dropped 2026-11-14: the pin passed (T = 3 works: each activation row has its own simdgroup group) and identity 36/36, but verify rows reach the Q4 pack's F16 `hc_*` tensors, and A/B (`PASS (tokens; bitwise)`, 40 pairs, A on the high mode) read MTP decode -0.36% code (CI -0.47..-0.18) and -0.50% prose (-0.55..-0.41). Child's r2/r3 kept; one `sf-keep(82)` comment above `ds4_gpu_mv_rows_name` records it.)

## 5. Closing

- [x] 5.1 Final tree (steps 2, 3, 4.1): `make -j8` no warnings; `make test -j8` every suite line ok; `make test-qwen4-kernels`, `make test-qwen4-metal-units` (145 PASS), `make test-qwen4-q2` pass; identity 36/36. Steps 2+3: `tests/model_gates.sh` all PASS on Q4 and Q2, `PARITY OK` on Q4 and Q2. Final tree: Q4 model gates all PASS, `PARITY OK` (10 prompts) on Q4 and Q2.
- [x] 5.2 `speed-bench/perf-record.md`: row `perf/95-mtp-last-row` against segment 1's start `91f225a` (plain and mtp-code; prose empty as for `82` and the sync): PASS (tokens), 20 pairs, MTP code decode 90.1 t/s (+26.0%, the sync row read +22.3%), plain decode +6.1%.
