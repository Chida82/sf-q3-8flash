# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c202/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Ceiling per append size at 54 GiB, 8K and 32K. Close by the proposal's rule.

## 2. S1 (design D2; no GPU)

- [ ] 2.1 Branch `perf/202-ssd-append-next-layer-reads`; every caller of the pending-load path with `rg`.
- [ ] 2.2 Early reads of the next layer for multi-row calls; model-less test: early-read slots are exact, protected, and survive a failed read.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.
- [ ] 2.4 Step review.

## 3. Measure (design D3)

- [ ] 3.1 Streamed equals resident on Q4 and Q2.
- [ ] 3.2 Appends at 54, then 48 and 60 GiB; capped decode kinds. Keep or drop by D3.

## 4. Closing

- [ ] 4.1 Final review pass; `docs/SSD_STREAMING.md` (appends).
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 202-ssd-append-next-layer-reads --strict`; report; land as one signed commit; archive; delete `$SCR/c202`.
