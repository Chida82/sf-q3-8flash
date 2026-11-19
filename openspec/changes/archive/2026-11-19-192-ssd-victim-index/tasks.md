# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c192/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Scan share of decode at 48, 54 and 60 GiB, the three `capped-*` kinds, 3 runs each. Close by D1 if under 1% at 54 GiB. *(On the 193 tree, 3 runs each, the scan time of a -n 1 run subtracted: share of decode at 54 GiB mtp-code 3.43%, mtp-prose 1.81%, plain 3.10%; 48 GiB 3.05 / 2.34 / 3.08%; 60 GiB 3.26 / 1.37 / 2.67%; 0.052-0.071 ms per scan. Above 1%: continues.)*

## 2. The index (design D2, D3; no GPU)

- [x] 2.1 Branch `perf/192-ssd-victim-index`; list every writer of an entry's rank, state and stamp with `rg`; review `188`'s scratch patch. *(Writers of the victim order: the hotness note, decay and resets; the cache hit (two sites), install and clear; the in-flight mark, the sequence wrap and clear_all; on `main` after 189 also the handshake service (its hits and in-flight marks). 188's patch (`scratch/188-eviction-replay:scratch-188/rank-per-layer-stamp.patch`) reviewed: it hoists the recency test into one stamp per layer, which shortens each compare, not the number of entries a search visits; not taken. The index was written from D2.)*
- [x] 2.2 The index behind `DS4_METAL_STREAM_EXPERT_VICTIM_SCAN=1` (full scan); the random-sequence test. *(Per-layer revision and a global epoch, bumped at every writer; the per-layer minimum keyed also by the pass, the row call position, the size class and, if it held in-flight entries, the completion sequence. `ds4_gpu_stream_expert_cache_plan_reuse` and `ds4_gpu_stream_expert_cache_take_reusable` visit layers by minimum and stop at the first that cannot hold a victim. `DS4_METAL_STREAM_EXPERT_VICTIM_SCAN=1` scans every entry, `=2` runs both at every search and aborts on any difference. Instead of a separate random-sequence driver the unit test runs a third time under `=2`: every search of its cache, eviction and recency cases is checked against the scan.)*
- [x] 2.3 `make -j8` with no warnings; `make test -j8`; `make test-qwen4-ssd-experts`. *(make -j8 no warnings; make test green; test_qwen4_ssd_experts PASS buffered, uncached and under the cross-check.)*

## 3. Measure (design D3, D4)

- [x] 3.1 Streamed equals resident on Q4 and Q2; eviction counters equal to `main`'s. *(Model runs under `=2` (capped-mtp-code and capped-plain at 10,725): no difference at any search. Same runs, main against the index: misses, evictions and recent_victims identical (46,216 / 35,491 / 10 and 43,122 / 32,397 / 0); search time 487 -> 196 ms and 596 -> 195 ms per run. Streamed tokens equal to resident on Q4 and Q2 (plain, both MTP kinds).)*
- [x] 3.2 A/B at 54 GiB, then 48 and 60. Keep or drop by D4. *(KEPT. 54 GiB against `main` (with 189): mtp-code +1.92% [+1.35%, +2.61%] (12 pairs), mtp-prose +0.39% [-1.78%, +1.16%] (12), plain +2.01% [+1.16%, +2.73%] (8); 48 GiB mtp-code +2.14% [+1.61%, +6.48%] (4); 60 GiB +1.27% [-0.72%, +3.48%] (6). Prefill within noise.)*

## 4. Closing

- [x] 4.1 Remove the switch unless measured otherwise; `docs/SSD_STREAMING.md` (eviction order: how the victim is found). *(The switch stays: the unit test cross-checks the index through it (`=2`). Docs: eviction order, how the victim is found.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Model gates on Q4 and Q2 all PASS (a first attempt was stopped by the memory guard at the host-paths gate, compressor +5.4 GiB in one second with 57-68 GiB of inactive file cache; the re-run passed); PARITY OK (10 prompts).)*
- [x] 4.3 `openspec validate 192-ssd-victim-index --strict`; report; land as one signed commit; archive. *(Valid; landed as one signed commit; archived.)*
