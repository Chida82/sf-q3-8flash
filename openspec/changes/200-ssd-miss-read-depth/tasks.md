# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c200/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 9 against 18 threads; splits of 2, 4 and 8 (scratch); 3 runs each at 54 GiB. Close by the proposal's rule.

## 2. S1 (design D2; no GPU)

- [ ] 2.1 Branch `perf/200-ssd-miss-read-depth`; callers of the pool with `rg`.
- [ ] 2.2 The chosen setting; a model-less case for split reads (exact bytes, a failed piece fails its tensor).
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D3)

- [ ] 3.1 Streamed equals resident on Q4 and Q2.
- [ ] 3.2 A/B at 54, 48 and 60 GiB; RAM-free once. Keep or drop by D3.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md`.
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 200-ssd-miss-read-depth --strict`; report; land as one signed commit; archive.
