# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c194/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Scratch trace build; four traces at 54 GiB (plain and MTP, code and prose), capped and RAM taken.
- [ ] 1.2 Whole-layer coverage, covered wait, wasted reads, predictor time; projection. Close by D1 if under 3%.

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
