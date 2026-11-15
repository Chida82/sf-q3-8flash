# Tasks

Starts from `main` with `90` landed. Model runs strictly sequential.

## 1. Where the cycle goes

- [ ] 1.0 Let `ab_bench.py --sections` judge MTP verify passes: the engine already prints `ds4: Qwen3.8 T=<n> GPU us/pass over 50 passes` for every T (verify rows included), but only after 50 passes of one T, which the MTP kinds' 128 tokens rarely reach. Parse the T>1 lines for the MTP kinds and lengthen their generation when `--sections` is on. Verify: an MTP `--sections` run reports T=2..4 rows.
- [x] 1.1 `ab_bench.py --sections moe_mid,moe_down,attn,gdn,head` with the MTP kinds, A = `765e9a5`, B = `main`; record per-group GPU time for T=1 and for the verify rows.
  2026-11-14 finding: `DS4_QWEN4_TIMING=2` prints decode and verify group times as one line per T (`ds4: Qwen3.8 T=<n> GPU us/pass`) every 50 passes of that T, and `ab_bench.py` parses only T=1; so with 128 tokens the MTP kinds report prefill only (T=2 printed in 22 of 74 runs, T=3/4 never). A run with the MTP kinds (765e9a5 vs 062d4c3, 22 pairs) read MTP prefill 2048 target groups -0.7% / -0.9%. The T=1 half runs with the plain kind per group (`$SCR/gpu/ab-97t1-*`). The verify-row half ran as direct bench runs with 640 tokens, ABBA x3 on both MTP prompts (`$SCR/gpu/p97/`).
  2026-11-14 results (Q4, A = 765e9a5, B = 062d4c3; `$SCR/gpu/p97/`, `$SCR/gpu/ab-97t1-*`). Verify passes, 640 tokens, DS4_QWEN4_TIMING=2, ABBA x3: B is slower per pass, T=2 +2.8% (code) / +2.9% (prose), T=3 +3.3%; the loss is moe_down +20.6..+22.7% and attn +7.0..+7.4%, everything else within 1.5%. T=1 (plain, sections, 2 pairs per group): attn -10.0%, gdn -0.8%, moe_mid and head gained share, moe_down unjudged (rc 3); whole decode pass -2.2..-4.8%. So #1238 sped up T=1 and the sync slowed T=2/3: the child's `70` MXFP4 down pass that D4 replaced served the verify rows (95 step 3), and the attention change is #1238's T=1 split. Also: at 640 tokens B took more cycles than A (code 311 vs 271, prose 408 vs 395) where 128 tokens showed 2.46 tokens/cycle on both; check whether the drafts changed.
  2026-11-14 follow-up: the moe_down half is recovered by `95` step 3 (M5 NR2 paired rows for MXFP4 down at T > 1; verify moe_down -20.4% at T=2, -22.6% at T=3; MTP decode +2.9% code / +2.4% prose). What remains of the verify-row loss is attention (+7%). The cycle counts split as A k1/k2/k3 = 6/161/104, B 32/229/50 (code, 640 tokens): B gets half as many 3-token cycles.
- [ ] 1.2 List the groups #1238 made faster at T=1 and not at T=2/3, with their share of a cycle.

## 2. Steps

- [ ] 2.1 For the largest group: a verify-row variant on #1238's kernel; kernel pin byte-exact vs single rows at the decode sizes.
- [ ] 2.2 `test_qwen4_mtp_identity.py --model <Q4>` SAME; `ab_bench.py --bitwise --kinds mtp-code,mtp-prose`; keep on a gain, one perf-record row.
- [ ] 2.3 Repeat for the next group while each step gains.

## 3. Q2

- [ ] 3.1 Repeat 2.2 on Q2 for every kept step.
