# Tasks

GPU: sections 3 and 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs only on streamed processes,
and never while a container or another model process is running. `$SCR` is
`~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c186/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Branch (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c fix/186-ssd-memory-pressure`.
- [ ] 1.2 Read the slab and slot code with every caller (`rg` the allocation, lock and eviction helpers). Write down in `$SCR/c186/steps.txt` what protects an entry today and where a layer boundary is.

## 2. Mechanism (design D1-D3; no GPU)

- [ ] 2.1 The pressure source, the recorded level, and the read at open.
- [ ] 2.2 Shrink by slab at a layer boundary; the floor computed with the plan.
- [ ] 2.3 Regrowth after the quiet period.
- [ ] 2.4 The injection seam and the model-less tests of D4. The step checks.
- [ ] 2.5 Step review: no allocation on the release path; no lock added to the read path.

## 3. Model checks (design D4, D5)

- [ ] 3.1 Injected warning and critical in mid-decode at emulated 48 GB: token gate against resident, plain and MTP, Q2 and Q4. Record the log lines.
- [ ] 3.2 The one real-signal run with the bounded helper and the kill criteria. Record whether a level was raised and at what helper size.
- [ ] 3.3 No-pressure cost: `ab_bench.py` at emulated 48 GB against `main`.

## 4. Review and closing

- [ ] 4.1 Final pass; remove the scratch-only patch.
- [ ] 4.2 `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row.
- [ ] 4.3 `docs/SSD_STREAMING.md`: "Memory plan" gains the pressure behaviour and its log lines.
- [ ] 4.4 `openspec validate 186-ssd-memory-pressure --strict` passes.
- [ ] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c186/`; archive the change (syncs the `ssd-streaming` delta).
