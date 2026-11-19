# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c200/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 9 against 18 threads; splits of 2, 4 and 8 (scratch); 3 runs each at 54 GiB. Close by the proposal's rule. *(Done 2026-11-19, Q4 at 54 GiB (10,725 slots), capped, uncached, 3 runs per setting, decode median and the summary's load_pread_avg. Threads (on `main` with 192): MTP code 9 / 18 = 34.16 / 33.81 t/s, 1.367 / 1.381 ms; plain 26.13 / 25.94, 1.066 / 1.064 ms. Split of each tensor read into N pieces on 16 KiB boundaries (scratch, on `main` cab1187, synchronous decode reads): MTP code N = 1 / 2 / 4 / 8: 33.63 / 33.11 / 32.41 / 28.45 t/s, 1.369 / 1.386 / 1.508 / 1.776 ms; plain 25.82 / 25.78 / 25.30 / 23.22, 1.053 / 1.062 / 1.153 / 1.317 ms. Deeper reads make each load slower, not faster: no setting improves decode by 2%. CLOSED by the proposal's rule.)*

## 2. S1 (design D2; no GPU)

- [x] 2.1 Branch `perf/200-ssd-miss-read-depth`; callers of the pool with `rg`. *(Not done: closed at step 0.)*
- [x] 2.2 The chosen setting; a model-less case for split reads (exact bytes, a failed piece fails its tensor). *(Not done: closed at step 0.)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(Not done: closed at step 0.)*

## 3. Measure (design D3)

- [x] 3.1 Streamed equals resident on Q4 and Q2. *(Not done: closed at step 0.)*
- [x] 3.2 A/B at 54, 48 and 60 GiB; RAM-free once. Keep or drop by D3. *(Not done: closed at step 0.)*

## 4. Closing

- [x] 4.1 `docs/SSD_STREAMING.md`. *(Not done: closed at step 0.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not done: closed at step 0.)*
- [x] 4.3 `openspec validate 200-ssd-miss-read-depth --strict`; report; land as one signed commit; archive. *(Valid; closed and archived with the step-0 record (docs only).)*
