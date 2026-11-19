# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c201/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Copy share of decode at 54 GiB, three kinds, 3 runs each. Close by the proposal's rule. *(Done 2026-11-19 on `main` 4089b60 with a scratch timer around the bounce `memcpy` (per pread task; per load the copy of the slowest task, which is the load's critical path since a decode load has about 8 tasks for 9 pool threads), Q4, 54 GiB (10,725 slots), capped, uncached, each run after an evict, 3 runs per kind, medians. Copy on the critical path over decode time: MTP code 0.76% (34.6 t/s), MTP prose 0.44% (40.3 t/s), plain 0.75% (26.2 t/s); the copy is 2.1-2.8% of the slowest task's time, the rest is the read. All threads' copy summed over decode: 6.3 / 2.0 / 4.1% (an upper bound that assumes no overlap). Prefill 8192: all threads' copy summed is about 10% of prefill time, about 1.2% spread over the 9 threads. Under 1% of decode on every kind: CLOSED by the proposal's rule. A Parallels VM (31 GiB, about 28% CPU) was running when the series started and was gone when it ended; a contended memory bus would make the copy slower, not faster, so the closing figure is if anything high.)*

## 2. S1 (design D2; no GPU)

- [x] 2.1 Branch `perf/201-ssd-uncached-zero-copy`; every reader of an entry's buffer and inner offset with `rg`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.2 Slots with slack, direct uncached reads; model-less cases at unaligned offsets in both read modes. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(Not run: closed after step 0, 2026-11-19.)*

## 3. Measure (design D3)

- [x] 3.1 Streamed equals resident on Q4 and Q2, both read modes. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 3.2 A/B at the same footprint, 54 then 48 and 60. Keep or drop by D3. *(Not run: closed after step 0, 2026-11-19.)*

## 4. Closing

- [x] 4.1 `docs/SSD_STREAMING.md` (memory plan: slot size). *(Not run: closed after step 0, 2026-11-19.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 4.3 `openspec validate 201-ssd-uncached-zero-copy --strict`; report; land as one signed commit; archive. *(Not run: closed after step 0, 2026-11-19.)*
