# Tasks

Starts from `main` with `90` landed. Model runs strictly sequential.

## 1. Where the cycle goes

- [x] 1.0 Let `ab_bench.py --sections` judge MTP verify passes: the engine already prints `ds4: Qwen3.8 T=<n> GPU us/pass over 50 passes` for every T (verify rows included), but only after 50 passes of one T, which the MTP kinds' 128 tokens rarely reach. Parse the T>1 lines for the MTP kinds and lengthen their generation when `--sections` is on. Verify: an MTP `--sections` run reports T=2..4 rows.
  2026-11-15: an MTP kind adds a `verify T=<n>` shape per verify size that reached 50 passes (an MTP run with none is a run failure) and generates 640 tokens under `--sections`; a pair is judged on a shape only when both runs have it. Verify passes are T = 2 and 3 only (`ds4_session_qwen4_spec_cycle`); T = 4 does not occur. A/A on the worktree (Q4, 5 valid pairs): `mtp-code` reports verify T=2 and T=3, `mtp-prose` T=2 (its 3 depth-3 cycles never reach 50 passes); `attn`-normalized ratios -0.0% (CI -0.1..+0.0), +0.6% (+0.6..+0.7) and +0.1% (-0.0..+0.2). `tests/test_ab_bench.py`: 30 tests OK, two new.
- [x] 1.1 `ab_bench.py --sections moe_mid,moe_down,attn,gdn,head` with the MTP kinds, A = `765e9a5`, B = `main`; record per-group GPU time for T=1 and for the verify rows.
  2026-11-14 finding: `DS4_QWEN4_TIMING=2` prints decode and verify group times as one line per T (`ds4: Qwen3.8 T=<n> GPU us/pass`) every 50 passes of that T, and `ab_bench.py` parses only T=1; so with 128 tokens the MTP kinds report prefill only (T=2 printed in 22 of 74 runs, T=3/4 never). A run with the MTP kinds (765e9a5 vs 062d4c3, 22 pairs) read MTP prefill 2048 target groups -0.7% / -0.9%. The T=1 half runs with the plain kind per group (`$SCR/gpu/ab-97t1-*`). The verify-row half ran as direct bench runs with 640 tokens, ABBA x3 on both MTP prompts (`$SCR/gpu/p97/`).
  2026-11-14 results (Q4, A = 765e9a5, B = 062d4c3; `$SCR/gpu/p97/`, `$SCR/gpu/ab-97t1-*`). Verify passes, 640 tokens, DS4_QWEN4_TIMING=2, ABBA x3: B is slower per pass, T=2 +2.8% (code) / +2.9% (prose), T=3 +3.3%; the loss is moe_down +20.6..+22.7% and attn +7.0..+7.4%, everything else within 1.5%. T=1 (plain, sections, 2 pairs per group): attn -10.0%, gdn -0.8%, moe_mid and head gained share, moe_down unjudged (rc 3); whole decode pass -2.2..-4.8%. So #1238 sped up T=1 and the sync slowed T=2/3: the child's `70` MXFP4 down pass that D4 replaced served the verify rows (95 step 3), and the attention change is #1238's T=1 split. Also: at 640 tokens B took more cycles than A (code 311 vs 271, prose 408 vs 395) where 128 tokens showed 2.46 tokens/cycle on both; check whether the drafts changed.
  2026-11-14 follow-up: the moe_down half is recovered by `95` step 3 (M5 NR2 paired rows for MXFP4 down at T > 1; verify moe_down -20.4% at T=2, -22.6% at T=3; MTP decode +2.9% code / +2.4% prose). What remains of the verify-row loss is attention (+7%). The cycle counts split as A k1/k2/k3 = 6/161/104, B 32/229/50 (code, 640 tokens): B gets half as many 3-token cycles.
  2026-11-15 correction: the A side of the 640-token verify runs above (`$SCR/gpu/p97`, and the cycle counts) was a mixed build. `ds4_metal.m` loads `metal/*.metal` relative to the working directory, and that queue ran 765e9a5's binaries from the main checkout, so A ran 765e9a5's host code on 062d4c3's kernels and generated a different greedy text on the code prompt ("0, 0, 0, ..." runs). See design.md. The verify-row group deltas above (moe_down +21%, attn +7%) are therefore not a before/after of the sync. The T=1 half came from `ab_bench.py`, which runs every bench in its own tree, and stands.
- [x] 1.2 List the groups #1238 made faster at T=1 and not at T=2/3, with their share of a cycle.
  2026-11-15, Q4, current main (A/A `--sections` run for the verify passes, direct `DS4_QWEN4_TIMING=2` plain runs at the same frontier 2048 for T=1). Share of a pass, and the verify pass over T=1:
  | group | T=1 share | T=2 pass / T=1 | T=3 pass / T=1 |
  |---|---|---|---|
  | gdn | 27.9% | 0.98-1.02 | 1.12 |
  | moe_mid | 14.1% | 1.49-1.63 | 2.30 |
  | attn | 12.7% | 1.08-1.12 | 1.31 |
  | hc_ffn | 11.7% | 0.94-0.98 | 1.09 |
  | hc_attn | 10.9% | 0.94-0.98 | 1.09 |
  | moe | 7.8% | 0.94-0.98 | 1.00 |
  | moe_down | 7.6% | 1.39-1.50 | 2.12 |
  | head | 6.5% | 0.96-1.02 | 1.28 |
  | ple | 0.8% | 0.84-0.87 | 0.90 |
  | whole pass | 19.5 ms | 1.08-1.14 | 1.38 |
  The second row's extra time is in moe_mid (+1350..1720 us), moe_down (+590..750 us) and attn (+200..300 us), the rest within the clock noise. None of it is a #1238 T=1 path the verify rows miss: on Q4 the expert passes run the T=1 kernels at verify sizes (Q4_K mid NR1/NSG 4; MXFP4 down NR2 from `95`), and the verify attention runs #1238's tile (`f768d14`) and merge (`6605c3c`) through the `82` rows kernels. The extra is each row's own experts and keys. On Q2 one is missed: #1238's folded Q2_K down + reduce (`4ed25e4`) runs at T=1 only. Q2 verify down costs 0.97 of T=1 per row (Q4: 0.70-0.75).
- [x] 1.3 The 3-token-cycle drop. Same prompt, each build run from its own tree, 640 tokens, `DS4_QWEN4_SPEC_TRACE=1`: 765e9a5 and main give identical tokens, identical drafts and accept/reject at every cycle, k1/k2/k3 = 32/229/50 (code) and 179/226/3 (prose) on both, with and without `DS4_QWEN4_TIMING=2`. The 765e9a5 binary run against a copy of 062d4c3's `metal/` reproduces 6/161/104 and the "0, 0, ..." text exactly. The predictor did not change; the drop was the mixed build (1.1 correction).

## 2. Steps

- [x] 2.1 For the largest group: a verify-row variant on #1238's kernel; kernel pin byte-exact vs single rows at the decode sizes.
  Attention (dropped): the verify rows already run #1238's tile and merge (1.2), so the one variant left was each verify row through the single-row core (one score/select/expand/decode/merge set per row, the T=1 dispatches themselves). Q4 code, 640 tokens, 2 alternating runs each under `DS4_QWEN4_TIMING=2`, tokens identical: verify `attn` +10.9% at T=2 and +21.0% at T=3 (normalized +11.6% / +22.6%). The rows kernels already cost less per row. Reverted.
  Q2 MoE down (kept): `kernel_qwen4_moe_down_reduce` (#1238 `4ed25e4`, T=1 only) takes the token from grid y with per-token offsets of every operand (zero at T=1), and the verify rows (T = 2, 3, row-exact flag, not deferred) take it on Q2_K down experts. Q4 runs MXFP4 down and is unchanged. Pin: `tests/test_qwen4_kernels.c` compares the fold with the verify dispatch (down, then reduce), output and residual, byte for byte at T = 1, 2, 3 on the model shape (E 2560, F 640, 10 slots, shared Q8), and under `DS4_TEST_QWEN4_MV_EXACT` at 6 slots and F 672. The suite had no pin for the fold before (90 4.1 names one; none was in the tree).
- [x] 2.2 `test_qwen4_mtp_identity.py --model <Q4>` SAME; `ab_bench.py --bitwise --kinds mtp-code,mtp-prose`; keep on a gain, one perf-record row.
  Identity: 36/36 SAME on Q4 and on Q2. The step only reaches Q2; on Q4 the final all-kinds run (5.x) is its A/B. Q2, `--bitwise --kinds mtp-code,mtp-prose`, A = main 661768f, 46 valid pairs, PASS (tokens; bitwise): MTP decode code +0.8% (range +0.1..+1.3, every pair positive), prose +1.0% (+0.6..+2.2); k2 cycle -0.9% / -1.0%, tokens per cycle unchanged, prefill 2048 -0.0%. Under `DS4_QWEN4_TIMING=2` the T=2 verify down + reduce went from 4061 to 3853 us per pass (-5%). Kept.
- [x] 2.3 Repeat for the next group while each step gains. No further group: on Q4 every verify group already runs its T=1 kernel (1.2), and on Q2 the IQ2_XXS gate/up kernel (#1238 `47c34fb`) already serves every T. What remains is each row's own experts and keys.

## 3. Q2

- [x] 3.1 Repeat 2.2 on Q2 for every kept step. The kept step is Q2's (2.2).

## 4. Gates

- [x] 4.1 `make -j8` without warnings; `make test -j8` (layer_pack 97/97, TP, server, ds4 tests, eval, sampling, sfctl all ok); `make test-qwen4-kernels` (all passed, the three new fold lines included); `tests/test_ab_bench.py` 30 OK; `openspec validate 97-mtp-verify-speed --strict` valid.
- [x] 4.2 `tests/model_gates.sh` with the mmproj and both vision fixtures: all PASS on Q4 and on Q2 (mtp-identity, mtp-limits, ds4_test, vision, host-paths).
- [x] 4.3 `SF_CHILD_DIR=<worktree> tools/parity-check.sh sf-q3-8flash <Q4>`: PARITY OK (10 prompts).
- [x] 4.4 Final `ab_bench.py --bitwise -m <Q4>` (all kinds) against main 661768f: PASS (tokens; bitwise), 24 pairs; plain decode -0.1%, MTP decode -0.1% code / +0.0% prose, tokens per cycle unchanged, prefill +512/+2048/MTP 2048 within 0.2%. Prefill 8192 read -2.9% (range -18.5..+0.1, 8 pairs); a plain-only rerun (14 pairs, bitwise PASS) read +1.0% (-16.4..+13.0) and decode +0.1%: noise on the first chunk, which no changed code reaches.
- [x] 4.5 perf-record row (Q2, against segment 1's start `91f225a`, plain and mtp-code as for `95`): PASS (tokens), 20 pairs; plain decode 58.8 t/s (+13.5%), MTP code decode 81.3 t/s (+16.6%; the last Q2 row, `82`, read +10.0%), tokens/cycle 1.91 (+4.5%), prefill 8192 +4.3%. The first Q2 row since `82`, so it carries the sync, `95`, `140` and `101` too. Thermal reached Heavy in part of the timed runs. Appended.
