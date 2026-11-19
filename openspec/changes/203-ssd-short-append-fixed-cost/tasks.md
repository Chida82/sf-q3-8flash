# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c203/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 GPU and CPU parts of a 64- and 256-token append at 54 GiB. Choose S1, S2, both or none by D2; close by the proposal's rule.

## 2. Build (design D2; no GPU)

- [ ] 2.1 Branch `perf/203-ssd-short-append-fixed-cost`; every caller of the touched path with `rg`.
- [ ] 2.2 The chosen step(s); model-less tests on the streamed MM shapes at small row counts.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D3)

- [ ] 3.1 Streamed equals resident on Q4 and Q2.
- [ ] 3.2 Appends at 54 GiB; capped decode kinds. Keep or drop by D3.

## 4. Closing

- [ ] 4.1 Final review pass; `docs/SSD_STREAMING.md` (appends).
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 203-ssd-short-append-fixed-cost --strict`; report; land as one signed commit; archive; delete `$SCR/c203`.
