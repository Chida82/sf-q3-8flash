# Tasks

GPU: every measurement. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs (`--simulate-used-memory`)
only on streamed processes, and never while a container or another model
process is running. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's files
go in `$SCR/c185/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Branch and baseline

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/185-ssd-expert-read-path`. Confirm `170` is landed or dropped and adjust D2 to what stands.
- [ ] 1.2 Baseline at emulated 48 GB, Q2 and Q4: streamed plain and MTP decode, prefill, peak footprint, and the stream timing summary (read ms, missing experts per layer). Record in `$SCR/c185/steps.txt`.

## 2. Step S1: uncached expert reads (design D1)

- [ ] 2.1 Second descriptor with `F_NOCACHE`; page-aligned reads; kill switch. Find every expert read site with `rg 'pread\(' ds4_metal.m` first.
- [ ] 2.2 The step checks. Streamed equals resident, token gate, Q2 and Q4, plain and MTP (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`).
- [ ] 2.3 Measure by D3, with `F_RDADVISE` on and off. Keep or drop; record the figures and the footprint.
- [ ] 2.4 Step review.

## 3. Step S2: next-layer read-ahead (design D2)

- [ ] 3.1 Step 0: record one routing trace per pack (decode, code and prose) behind a scratch-only patch; compute the three predictors' coverage and waste offline. Record the table. Stop S2 here if none passes D2's threshold.
- [ ] 3.2 Implement the first passing predictor. Add a model-less test: a wrong prediction changes no computed expert, and read-ahead never evicts a protected entry.
- [ ] 3.3 The step checks and the token gates of 2.2.
- [ ] 3.4 Measure by D3 against S1. Keep or drop.
- [ ] 3.5 Step review.

## 4. Review and closing

- [ ] 4.1 Final pass: remove the kill switches unless D3 found a step machine dependent; no dead code.
- [ ] 4.2 `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row.
- [ ] 4.3 `docs/SSD_STREAMING.md`: the read path and the new measured table.
- [ ] 4.4 `openspec validate 185-ssd-expert-read-path --strict` passes.
- [ ] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c185/`; archive the change.
