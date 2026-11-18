# Tasks

GPU: every measurement. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs (`--simulate-used-memory`)
only on streamed processes, and never while a container or another model
process is running. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's files
go in `$SCR/c185/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

**Outcome (2026-11-18): S1 dropped at 2.3; S2 stopped after step 0 (3.1).**
No code lands. Figures and tables: design D5.

## 1. Branch and baseline

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/185-ssd-expert-read-path`. Confirm `170` is landed or dropped and adjust D2 to what stands. *(`170` was dropped (`8701148`): the ordinary per-layer load sequence stands, D2 as written.)*
- [x] 1.2 Baseline at emulated 48 GB, Q2 and Q4: streamed plain and MTP decode, prefill, peak footprint, and the stream timing summary (read ms, missing experts per layer). Record in `$SCR/c185/steps.txt`. *(Plain kind only, `main`, each run starting with the GGUF's pages dropped from the page cache: Q2 decode 30.2 t/s, prefill 1135 / 470 / 857 t/s, plan 19.36 GiB with 2464 cached experts (3.42 GiB), peak footprint 90.6 GiB with 80 locked; Q4 decode 18.9 t/s, prefill 902 / 255 / 490, plan 19.57 GiB with 978 experts (2.47 GiB), footprint 89.4 GiB. Timing summary, Q2: 2.70 missing experts per split layer, load pread 0.743 ms on average (prefill staging included). The MTP kinds were not run: S1 was decided on the plain kind.)*

## 2. Step S1: uncached expert reads (design D1)

- [x] 2.1 Second descriptor with `F_NOCACHE`; page-aligned reads; kill switch. Find every expert read site with `rg 'pread\(' ds4_metal.m` first. *(All expert reads go through `ds4_gpu_stream_expert_pread_into`; the descriptor is derived from the registered one with `F_GETPATH`, so an unlinked file, as in the unit test, keeps the buffered path. Commit `dc50997` on the branch.)*
- [x] 2.2 The step checks. Streamed equals resident, token gate, Q2 and Q4, plain and MTP (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`). *(Build with no warnings; `make test` green; `tests/test_qwen4_ssd_experts` on Metal 103 PASS, 0 FAIL, on its buffered fallback. Q2 streamed against resident: `PASS (tokens)`, plain and both MTP kinds. Q4: tokens equal to `main`'s streamed run at emulated 48 GB, plain kind; streamed against resident not run, dropped at 2.3.)*
- [x] 2.3 Measure by D3, with `F_RDADVISE` on and off. Keep or drop; record the figures and the footprint. *(**Dropped.** Q2 plain decode 30.2 -> 20.3 t/s, -33.3% [-34.0%, -31.3%], 8 pairs, clean windows; Q4 18.9 -> 11.2, 2 pairs. Footprint unchanged. `F_RDADVISE` is never issued on the Qwen path, so there was nothing to switch. `main`'s code restored.)*
- [ ] 2.4 Step review. Not run: dropped at 2.3.

## 3. Step S2: next-layer read-ahead (design D2)

- [x] 3.1 Step 0: record one routing trace per pack (decode, code and prose) behind a scratch-only patch; compute the three predictors' coverage and waste offline. Record the table. Stop S2 here if none passes D2's threshold. *(Four traces, table in design D5. Predictors 1 and 2 fail; predictor 3, the next layer's router on this layer's input, passes with its top 6 on all four: 32-38% of misses, wasted reads 0.45-0.84 of the covered ones.)*
- [ ] 3.2 Not built (night of 2026-11-18). A scratch probe of the cheapest form, a page-cache hint for predictor 3's experts, read -0.8% on Q2 and -3.6% / -5.8% on Q4 against the same prediction work without the hint; read-ahead into cache slots did not fit the night and goes to a new proposal (design D5). Implement the first passing predictor. Add a model-less test: a wrong prediction changes no computed expert, and read-ahead never evicts a protected entry.
- [ ] 3.3 The step checks and the token gates of 2.2. Not run: 3.2.
- [ ] 3.4 Measure by D3 against S1. Keep or drop. Not run: 3.2.
- [ ] 3.5 Step review. Not run: 3.2.

## 4. Review and closing

- [ ] 4.1 Final pass: remove the kill switches unless D3 found a step machine dependent; no dead code. Not run: no code lands.
- [ ] 4.2 Not run: no code lands. `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row.
- [x] 4.3 `docs/SSD_STREAMING.md`: the read path and the new measured table. *(One paragraph: the page cache as the second-level cache at the emulated sizes, and the uncached-read figures.)*
- [x] 4.4 `openspec validate 185-ssd-expert-read-path --strict` passes.
- [x] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c185/`; archive the change. *(Closed by the night executor under the standing rule for local `main`: one signed docs commit; push is the owner's.)*
