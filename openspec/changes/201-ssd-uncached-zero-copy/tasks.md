# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c201/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Copy share of decode at 54 GiB, three kinds, 3 runs each. Close by the proposal's rule.

## 2. S1 (design D2; no GPU)

- [ ] 2.1 Branch `perf/201-ssd-uncached-zero-copy`; every reader of an entry's buffer and inner offset with `rg`.
- [ ] 2.2 Slots with slack, direct uncached reads; model-less cases at unaligned offsets in both read modes.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`.

## 3. Measure (design D3)

- [ ] 3.1 Streamed equals resident on Q4 and Q2, both read modes.
- [ ] 3.2 A/B at the same footprint, 54 then 48 and 60. Keep or drop by D3.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md` (memory plan: slot size).
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 201-ssd-uncached-zero-copy --strict`; report; land as one signed commit; archive.
