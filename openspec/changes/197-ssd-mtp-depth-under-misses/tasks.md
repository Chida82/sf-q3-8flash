# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c197/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Forced depth 2 and 3 against the default at 54 GiB, MTP code, prose, copy; winners at 48 and 60. Close by the proposal's rule.

## 2. S1 (design D2; no GPU)

- [ ] 2.1 Branch `perf/197-ssd-mtp-depth-under-misses`; every reader of the depth window with `rg`.
- [ ] 2.2 The rule, streaming sessions only; a model-less test of the rule's decisions on synthetic windows.
- [ ] 2.3 `make -j8` with no warnings; `make test -j8`.

## 3. Measure (design D3)

- [ ] 3.1 Streamed equals resident on Q4 and Q2 (MTP kinds).
- [ ] 3.2 A/B at 54, 48 and 60 GiB; resident MTP `--bitwise`. Keep or drop by D3.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md`.
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 197-ssd-mtp-depth-under-misses --strict`; report; land as one signed commit; archive.
