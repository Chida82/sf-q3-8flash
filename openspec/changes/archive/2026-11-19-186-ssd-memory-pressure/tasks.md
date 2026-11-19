# Tasks

GPU: sections 3 and 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs only on streamed processes,
and never while a container or another model process is running. `$SCR` is
`~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c186/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Branch (no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/186-ssd-memory-pressure`. *(2026-11-19.)*
- [x] 1.2 Read the slab and slot code with every caller (`rg` the allocation, lock and eviction helpers). Write down in `$SCR/c186/steps.txt` what protects an entry today and where a layer boundary is. *(An entry is protected by its in-flight sequence, the call's routed ids and, on rows, the last-pass rule. The boundary is `ds4_gpu_qwen4_moe_stream_tensor` after its drain and the pending-load join, before the ids are read; the Q2 handshake does not drain, so a due action sends that one layer down the ordinary path. Release unit: the newest slab, since slabs are addressed by start slot.)*

## 2. Mechanism (design D1-D3; no GPU)

- [x] 2.1 The pressure source, the recorded level, and the read at open. *(`DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` created at the first streamed `ds4_gpu_set_streaming_expert_cache_budget`, cancelled in `ds4_gpu_cleanup`; the handler stores the level and bumps an event count. `kern.memorystatus_vm_pressure_level` at open: not normal opens at the floor.)*
- [x] 2.2 Shrink by slab at a layer boundary; the floor computed with the plan. *(Warning: newest slabs released until the size is at most three quarters of the plan; critical: down to the floor, one layer's 512 experts, so any chunk fits and no unplanned staging is needed; never below it. The size caps the configured budget. Entries outside slabs are pruned to the cap.)*
- [x] 2.3 Regrowth after the quiet period. *(After 30 s at the normal level, one slab, allocated at once when the cap is full of slabs (a failed allocation ends the step and waits another quiet period), else the cap rises by a slab's slots; never past the plan.)*
- [x] 2.4 The injection seam and the model-less tests of D4. The step checks. *(`ds4_gpu_stream_expert_cache_test_pressure(level, quiet_ms)`; `check_pressure` in `tests/test_qwen4_ssd_experts.c` on the Q2 and Q4 formats: warning to three quarters by whole slabs, the shrunk size held under further loads, critical to the floor, a warning at the floor never grows it, regrowth one slab at a time to the plan and never past it, every row (the one whose call shrinks included) exact against the mapped reference. Not covered: a failed slab allocation during regrowth (no seam for it; three lines). make 0 warnings; make test green; the SSD test PASS buffered and with the victim cross-check.)*
- [x] 2.5 Step review: no allocation on the release path; no lock added to the read path. *(Release clears entries, munlocks slots, compacts the free list in place and drops the slab buffer; the read path gains one relaxed atomic load per streamed layer call, plus a clock read only while shrunk.)*

## 3. Model checks (design D4, D5)

- [x] 3.1 Injected warning and critical in mid-decode at emulated 48 GB: token gate against resident, plain and MTP, Q2 and Q4. Record the log lines. *(Run in the capped condition instead (54 GiB: Q4 10,725, Q2 18,563 slots, uncached), where the cache is large enough to shrink: the emulated plan holds about 1,000 Q4 slots, two floors. Scratch injection by decode pass, warning or critical at pass 100 (MTP 60), normal 100 (MTP 60) passes later with a 3 s quiet period: tokens identical to resident in all 8 runs. Q4: `warning: expert cache 10725 -> 7895 experts (27.17 -> 20.00 GiB), 5 slabs`, regrowth `7895 -> 9474 -> 10725`; `critical: 10725 -> 1579 (27.17 -> 4.00 GiB), 1 slabs`, regrowth by 1,579-slot slabs. Q2: warning 18563 -> 13923, critical -> 2880.)*
- [x] 3.2 The one real-signal run with the bounded helper and the kill criteria. Record whether a level was raised and at what helper size. *(Q4, MTP, 2048 + 512 at emulated 48 GB (80 GiB lock; plan 11.68 GiB, 1,008 slots), a helper holding 2 to 12 GiB in 2 GiB steps: wired 95.0 GiB, free 0.1 GiB, compressor 1.2 -> 5.9 GiB, no kill criterion fired, and no pressure level reached the engine. Recorded; not pushed further, per D4.)*
- [x] 3.3 No-pressure cost: `ab_bench.py` at emulated 48 GB against `main`. *(In the capped condition (`190`), uncached, tokens PASS in every invocation; bootstrap 95% CI of the median pair ratio. 54 GiB: MTP code decode 34.80 -> 34.78 t/s, -0.20% [-0.63%, +0.24%] (12 pairs), prefill -0.11% [-0.35%, +0.30%]; MTP prose 40.80 -> 40.31, -1.20% [-1.79%, +0.09%] (12); plain 26.39 -> 26.38, -0.11% [-0.23%, +0.21%] (12; at 8 pairs it read -0.13% [-0.53%, -0.04%], so a third invocation was added). 48 GiB MTP code +0.0% (4), 60 GiB +0.2% (6). No metric's CI wholly below zero.)*

## 4. Review and closing

- [x] 4.1 Final pass; remove the scratch-only patch. *(The injection patch lived only in a scratch worktree, never on the branch. Final pass: a shrink caps at the released size (not the target, which let a small slab regrow at once); regrowth adds a slab's worth even before any slab exists; entries outside slabs are pruned to the cap; the slab append is one helper shared by the allocator and regrowth.)*
- [x] 4.2 `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row. *(2026-11-19 on 2aae95b: model gates Q4 and Q2 all PASS (MTP identity, limits, turns, ds4_test, vision, host paths); PARITY OK (10 prompts); resident `--bitwise` against `main`: PASS (tokens; bitwise), 24 runs. Record row: `| fix/186-ssd-memory-pressure | 2026-11-19 | this row's commit | Qwen3.8-Flash-Next-Q4.gguf | 24 | PASS | 57.4 (+0.1%) | 1502.2 (+0.5%) | 1038.5 (+0.2%) | 1371.9 (+0.5%) | 89.8 (-0.0%) | 2.46 (+0.0%) | 1456.3 (-0.1%) | 66.0 (-0.1%) | 1.49 (+0.0%) | 1448.6 (+0.1%) |`.)*
- [x] 4.3 `docs/SSD_STREAMING.md`: "Memory plan" gains the pressure behaviour and its log lines. *("Memory pressure" subsection.)*
- [x] 4.4 `openspec validate 186-ssd-memory-pressure --strict` passes.
- [x] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c186/`; archive the change (syncs the `ssd-streaming` delta). *(Landed by the night executor, 2026-11-19; report in the night log.)*
