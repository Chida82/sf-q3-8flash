# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard (the neighbour runs inside the guarded tree).
`$SCR/c195/` holds this change's files.

## 1. Neighbour and step 0 (design D1, D2)

- [ ] 1.1 The scratch neighbour tool; a dry run without a model: it holds 60 GiB, the guard sees it, nothing wires.
- [ ] 1.2 Step 0 table at 54 GiB. Choose S1, S2, both or none by D2; close if neither can pass D4.

## 2. Build (design D3; no GPU)

- [ ] 2.1 Branch `perf/195-ssd-pressure-aware-read-mode`; every caller of the read pool with `rg`.
- [ ] 2.2 The chosen step(s) behind kill switches; model-less tests for the mode choice (class, pressure, hold time).
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D4)

- [ ] 3.1 Streamed equals resident on Q4 and Q2.
- [ ] 3.2 With and without the neighbour at 54 GiB, then 48 and 60. Keep or drop by D4.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md` (read modes and when each applies).
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 195-ssd-pressure-aware-read-mode --strict`; report; land as one signed commit; archive.
