# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c193/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Scratch counter; Q4 and Q2, three footprints, plain and MTP. Close by D1 if Q4 takes the owned path. *(A counter at the owned-path branch of `ds4_gpu_qwen4_moe_stream_tensor` (both owned reads go through it), on a scratch build of 190; capped, uncached, 8192-token context, 128 generated. Q4 at 7,326 / 9,701 / 12,076 slots, plain and MTP: zero calls. Q2 at 14,151 / 18,467 / 22,784 slots (the same footprints): only the MTP layer (48), 83 row calls per MTP run, by size class; plain zero.)*

## 2. The rule (design D2, D3; no GPU)

- [x] 2.1 Branch `perf/193-ssd-staging-when-needed`; every reader of `ssd_streaming_prefill_headroom_bytes` with `rg`. *(Readers of `ssd_streaming_prefill_headroom_bytes`: the memory report (planned line), the generic static-lock fit check (not reached for Qwen), and an unused argument of the CPU graph. `qwen4_streaming_staging_bytes` has one caller, the admission.)*
- [x] 2.2 The rule in the plan, the plan line naming it; a test that a cache under 512 slots keeps the reserve. *(The staging function takes `cache_holds_layer`: then layers of the trunk expert size get no window. The admission plans without the trunk windows and keeps them when the cache that leaves holds fewer than 512 experts; a later session is checked against the reserve its engine planned. The plan line names the case. `tests/test_qwen4_memory.c`: Q2 with MTP keeps only the predictor window, without MTP none, a uniform pack none, and the old reserve without the flag. The admission rule itself is checked on the model (3.1: 400 slots plan the trunk windows back).)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(make -j8 no warnings; make test green; test_qwen4_memory OK; test_qwen4_ssd_experts PASS buffered and uncached.)*

## 3. Measure (design D4)

- [x] 3.1 Slot counts for 48, 54 and 60 GiB after the change. *(One open each at `--ctx-alloc 262144 --mtp`: 8,350 / 10,725 / 13,100 slots plan 47.44 / 53.44 / 59.45 GiB, the same totals as 7,326 / 9,701 / 12,076 before (projector 0.57 GiB added: 48 / 54 / 60). 400 slots: 2.59 GiB staging, "trunk layers". Q2 with MTP at 9,000: 1.29 GiB, "off-size layers only".)*
- [x] 3.2 Streamed equals resident on Q4 and Q2. *(`ab_bench.py`, the 193 build against itself with B streamed (4,915 slots on Q4, 9,000 on Q2), plain and both MTP kinds: PASS (tokens) on both packs.)*
- [x] 3.3 A/B at the same footprint, 54 then 48 and 60. Keep or drop by D4. *(KEPT. Same planned footprint, main at the old slots against 193 at +1,024, capped, RAM taken. 54 GiB: mtp-code decode +8.54% [+7.35%, +9.51%] (12 pairs), mtp-prose +1.93% [-1.33%, +6.99%] (12), plain +6.38% [+4.68%, +7.14%] (4). 48 GiB mtp-code +8.77% [+8.62%, +9.29%] (4); 60 GiB +7.86% [+6.18%, +8.16%] (6); 48/60 on mtp-code only (time). First 8192-token prefill -0.8% to -1.3% (prose -0.89% [-1.10%, -0.52%] wholly below zero): main at the larger slot count loses the same (-0.86%), mlock 439 -> 483 ms, and the appends in the same process gain (+512: +11.3%, +2048: +6.1%, 3 runs each). Kept by the owner rule of 2026-11-18 in design D4. Planned totals equal on both sides (3.1).)*

## 4. Closing

- [x] 4.1 `docs/SSD_STREAMING.md` memory plan; `190`'s footprint table. *(Memory plan; the capped footprint table with the new slot counts; AGENTS.md bench line at 10,725.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Model gates on Q4 and Q2 all PASS; PARITY OK (10 prompts).)*
- [x] 4.3 `openspec validate 193-ssd-staging-when-needed --strict`; report; land as one signed commit; archive. *(Valid; landed as one signed commit; archived.)*
