# Tasks

GPU: sections 1 and 3. Model runs strictly sequential, each under the
one-second memory guard. `$SCR/c196/` holds this change's files.

## 1. Step 0 (design D1)

- [ ] 1.1 Footprint against context length at the service's allocation. Close by the proposal's rule if the untouched share up to 64K is under 4 GiB.

## 2. Build (design D2, D3; no GPU; after 186)

- [ ] 2.1 Branch `perf/196-ssd-footprint-target`; every reader of `graph_bytes` and of the cache budget with `rg`.
- [ ] 2.2 The option in CLI and server, the accounting, the check before a chunk, shrink through `186`.
- [ ] 2.3 Model-less tests: the cache never exceeds the plan; the check shrinks before a chunk that would pass N; a context that alone passes N fails with the figures.
- [ ] 2.4 `make -j8` with no warnings; `make test -j8`; `./ds4_test --server`.

## 3. Measure (design D4)

- [ ] 3.1 Streamed equals resident on Q4.
- [ ] 3.2 A/B at 54 GiB; the 128K run with the footprint sampled. Keep or drop by D4.

## 4. Closing

- [ ] 4.1 `docs/SSD_STREAMING.md`, `docs/SERVER.md` if the option is listed there.
- [ ] 4.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh`: `PARITY OK`.
- [ ] 4.3 `openspec validate 196-ssd-footprint-target --strict`; report; land as one signed commit; archive.
