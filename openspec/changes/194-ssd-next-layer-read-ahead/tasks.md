# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c194/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Scratch trace build; four traces at 54 GiB (plain and MTP, code and prose), capped and RAM taken. *(Done 2026-11-19 on `main` cab1187 (with 189 and 193), Q4 at 10,725 slots, capped, uncached, 8192-token context, 512 generated. Scratch probe (never committed): at each streamed row call of layer L the next layer's router (logits only) runs on L's FFN input; the next call prints its top 10 per row with their cached bits, and every row call prints its selected and missing ids and its wait (drain end to experts ready). Top-k on logits approximates the router's selection.)*
- [x] 1.2 Whole-layer coverage, covered wait, wasted reads, predictor time; projection. Close by D1 if under 3%. *(Miss calls fully covered, top 6 / top 10: MTP code 13.1% / 26.0%, MTP prose 14.7 / 30.8%, plain code 16.9 / 32.0%, plain prose 15.5 / 31.8%. Their wait as a share of decode: 4.0 / 8.7%, 2.3 / 4.8%, 4.8 / 9.6%, 1.5 / 3.1%; pooled over the four traces 3.3% (top 6) and 6.8% (top 10). Wasted reads per covered call 0.20-0.56 (top 6), 0.63-1.55 (top 10). Predictor cost about 1.3% of decode (29.23 against 29.63 t/s, its read-back and CPU top-k included). Projection for top 10: about 5.4%, above the 3% of D1: LEFT OPEN for S1. The projection is an upper bound: a covered wait is hidden only if the early read finishes before the next layer needs it (a load waits about 1.0-1.4 ms; a layer's GPU time is about 0.3-0.5 ms).)*

## 2. S1 (design D2, D3; no GPU)

- [ ] 2.1 Branch `perf/194-ssd-next-layer-read-ahead`; callers of the streamed MoE call and the read pool with `rg`.
- [ ] 2.2 The predictor's encode, the early reads, their guards, behind `DS4_QWEN4_STREAM_READ_AHEAD=0`.
- [ ] 2.3 Model-less tests: a wrong prediction changes no computed expert; an early read never evicts a protected or last-pass entry; an in-flight early read is waited for when selected.
- [ ] 2.4 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D4)

- [ ] 3.1 Streamed equals resident on Q4 and Q2, the switch on and off.
- [ ] 3.2 A/B at 54 GiB, then 48 and 60, and once RAM-free. Keep or drop by D4.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md`; the switch kept only if measured machine dependent.
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 194-ssd-next-layer-read-ahead --strict`; report; land as one signed commit; archive.
