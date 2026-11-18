# Tasks

GPU: sections 3 and 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs only on streamed processes,
never while a container or another model process is running, and under the
one-second memory guard. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's
files go in `$SCR/c188/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Step 0: trace replay (design D2; no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/188-ssd-expert-eviction-recency`. Take the traces and tools from `perf/185-ssd-expert-read-path` (`1a4b6fc`, `scratch-185/`) into `$SCR/c188/`; nothing from that branch is committed here.
- [ ] 1.2 The cache replay with the caps and the victim order of `main`. Check it reproduces the recorded misses per token at W = 0.
- [ ] 1.3 Misses per token for each W on the four traces. Record the table in `$SCR/c188/steps.txt`. Apply D2: choose W, or close as "measured, not needed".

## 2. The rule (design D1; no GPU)

- [ ] 2.1 The per-entry token stamp and the two-pass victim choice. Find every site that writes `last_used` or clears an entry with `rg` first.
- [ ] 2.2 The redirected-victims counter in the timing summary; the `DS4_METAL_STREAM_EXPERT_RECENT_TOKENS` switch.
- [ ] 2.3 Model-less test: a recent entry survives while an older candidate exists; when all are recent the cap still holds; protected and in-flight entries are never taken. The step checks.
- [ ] 2.4 Step review.

## 3. Model checks (design D3, D4)

- [ ] 3.1 Streamed equals resident, token gate, Q2 and Q4, plain and MTP (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`).
- [ ] 3.2 The A/B of D3 on Q2, then Q4. Keep or drop; record pooled CIs, pairs and misses per token from the timing summary.
- [ ] 3.3 The same A/B once without page-cache eviction, Q2, as information.
- [ ] 3.4 The cache-size curve of D4.

## 4. Review and closing

- [ ] 4.1 Final pass: keep the switch only if W turned out pack dependent; no dead code.
- [ ] 4.2 `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row.
- [ ] 4.3 `docs/SSD_STREAMING.md`: the eviction order, and the measured table if the streamed rates changed.
- [ ] 4.4 `openspec validate 188-ssd-expert-eviction-recency --strict` passes.
- [ ] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c188/`; archive the change.
