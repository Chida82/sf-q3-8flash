# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c197/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Forced depth 2 and 3 against the default at 54 GiB, MTP code, prose, copy; winners at 48 and 60. Close by the proposal's rule. *(Done 2026-11-19 on `main` with 192, 54 GiB (10,725 slots), capped, by hand (the harness sets `--env` on both sides only), 3 runs per cell, decode t/s default / depth 2 / depth 3: MTP code 34.62 / 33.96 / 35.12 (depth 3 +1.4%, runs 34.82-35.22 against 34.11-34.64); MTP prose 37.17 / 37.45 / 34.13 (depth 3 -8.2%); copy kind (2,048 tokens, 128 generated) 33.69 / 33.66 / 34.03 (depth 3 +1.0%, ranges apart). Forced depth 3 beats the default on code and copy and loses on prose, so the rule is not closed: LEFT OPEN for S1 (a streaming-aware threshold), with a small ceiling (about 1-1.5%). 48 and 60 GiB not run.)*

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
