# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c192/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Scan share of decode at 48, 54 and 60 GiB, the three `capped-*` kinds, 3 runs each. Close by D1 if under 1% at 54 GiB.

## 2. The index (design D2, D3; no GPU)

- [ ] 2.1 Branch `perf/192-ssd-victim-index`; list every writer of an entry's rank, state and stamp with `rg`; review `188`'s scratch patch.
- [ ] 2.2 The index behind `DS4_METAL_STREAM_EXPERT_VICTIM_SCAN=1` (full scan); the random-sequence test.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D3, D4)

- [ ] 3.1 Streamed equals resident on Q4 and Q2; eviction counters equal to `main`'s.
- [ ] 3.2 A/B at 54 GiB, then 48 and 60. Keep or drop by D4.

## 4. Closing

- [ ] 4.1 Remove the switch unless measured otherwise; `docs/SSD_STREAMING.md` (eviction order: how the victim is found).
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 192-ssd-victim-index --strict`; report; land as one signed commit; archive.
