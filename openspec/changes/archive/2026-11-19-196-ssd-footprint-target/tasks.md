# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c196/` holds this change's files.

## 1. Step 0 (design D1)

- [x] 1.1 Footprint against context length at the service's allocation. Close by the proposal's rule if the untouched share up to 64K is under 4 GiB. *(Done 2026-11-19 on `main` 60e5189, Q4, `--ctx-alloc 262144 --mtp`, 10,725 slots (plan 53.44 GiB: KV 8.33 + buffers 11.68 + static 6.32 + cache 27.10; no projector in the bench), uncached reads, evicted GGUF. One process prefilled 2,048 / 16,384 / 65,536 / 131,072 / 253,952 tokens in sequence (`-n 0`: decoding at each frontier would replay the prefix without snapshots, which hold their own memory); a second process decoded 16 MTP tokens after 2,048. `footprint -p <bench pid> -f bytes` every second and at each frontier. Footprint: 43.80 GiB at 2K, 43.99 at 16K, 64K and 128K, 44.00 peak through 254K; the 16-token decode run peaked at 43.57. Parts at 16K-128K: IOAccelerator (graphics) 43.35 GiB, of which the expert cache 27.10 (full from the first prefill) and the context and graph buffers 16.25 against 20.01 planned; malloc 0.43; the 6.34 GiB of static weights are locked but counted as clean mapped file, not footprint. Held = footprint + static = 50.1-50.3 GiB against 53.44 planned: the untouched share is 3.1-3.3 GiB and does not change with context length. The KV and graph buffers are touched in full at allocation; about 3.8 GiB of the graph reserve is never touched at any length. Under 4 GiB up to 64K (and beyond): CLOSED by the proposal's rule. `190`'s "about 12 GiB under the plan" counted the static weights as free and the then-planned 2.59 GiB of staging; `docs/SSD_STREAMING.md` corrected.)*

## 2. Build (design D2, D3; no GPU; after 186)

- [x] 2.1 Branch `perf/196-ssd-footprint-target`; every reader of `graph_bytes` and of the cache budget with `rg`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.2 The option in CLI and server, the accounting, the check before a chunk, shrink through `186`. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.3 Model-less tests: the cache never exceeds the plan; the check shrinks before a chunk that would pass N; a context that alone passes N fails with the figures. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 2.4 `make -j8` with no warnings; `make test -j8`; `./ds4_test --server`. *(Not run: closed after step 0, 2026-11-19.)*

## 3. Measure (design D4)

- [x] 3.1 Streamed equals resident on Q4. *(Not run: closed after step 0, 2026-11-19.)*
- [x] 3.2 A/B at 54 GiB; the 128K run with the footprint sampled. Keep or drop by D4. *(Not run: closed after step 0, 2026-11-19.)*

## 4. Closing

- [x] 4.1 `docs/SSD_STREAMING.md`, `docs/SERVER.md` if the option is listed there. *(The step 0 figure replaces the "12 GiB under the plan" sentence in "Capped RAM", 2026-11-19.)*
- [x] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`. *(Not run: docs only, closed after step 0, 2026-11-19.)*
- [x] 4.3 `openspec validate 196-ssd-footprint-target --strict`; report; land as one signed commit; archive. *(Closed after step 0, 2026-11-19.)*
