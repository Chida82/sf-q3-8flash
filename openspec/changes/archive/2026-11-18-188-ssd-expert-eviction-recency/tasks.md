# Tasks

GPU: sections 3 and 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Memory-locked runs only on streamed processes,
never while a container or another model process is running, and under the
one-second memory guard. `$SCR` is `~/.sf/q3-8flash/scratch`; this change's
files go in `$SCR/c188/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Step 0: trace replay (design D2; no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/188-ssd-expert-eviction-recency`. Take the traces and tools from `perf/185-ssd-expert-read-path` (`1a4b6fc`, `scratch-185/`) into `$SCR/c188/`; nothing from that branch is committed here. The traces had been deleted with `185`'s scratch: recorded again, with the cache dumped at each decode segment's start.
- [x] 1.2 The cache replay with the caps and the victim order of `main`. Check it reproduces the recorded misses per token at W = 0. It reproduces the recorded cache before every load (9216 per trace); today's budgets are smaller than `185`'s, so the counts are 129.2 / 276.5 / 244.4 / 356.0.
- [x] 1.3 Misses per token for each W on the four traces. Record the table in `$SCR/c188/steps.txt`. Apply D2: choose W, or close as "measured, not needed". Not closed; no W meets the choice rule (design D5).

## 2. The rule (design D1; no GPU)

- [x] 2.1 The per-entry token stamp and the two-pass victim choice. Find every site that writes `last_used` or clears an entry with `rg` first. The victim sites of the Qwen row path are the batch plan and the scalar scan, not `prune_layer` (design, Context).
- [x] 2.2 The redirected-victims counter in the timing summary; the `DS4_METAL_STREAM_EXPERT_RECENT_TOKENS` switch. The counter is `recent_victims`, the victims taken although recent: in the replay nearly every victim is "redirected", which says nothing. The switch served the token windows and went with them (4.1).
- [x] 2.3 Model-less test: a recent entry survives while an older candidate exists; when all are recent the cap still holds; protected and in-flight entries are never taken. The step checks. In-flight entries are not staged by the new case: the scans' in-flight skip is untouched and the split cases of the same test cover it.
- [x] 2.4 Step review.

## 3. Model checks (design D3, D4)

- [x] 3.1 Streamed equals resident, token gate, Q2 and Q4, plain and MTP (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming`).
- [x] 3.2 The A/B of D3 on Q2, then Q4. Keep or drop; record pooled CIs, pairs and misses per token from the timing summary. Two token windows dropped, the one-pass window kept (design D5). Misses per token are from traces of the final code, not from the summary, which does not separate decode from prefill.
- [x] 3.3 The same A/B once without page-cache eviction, Q2, as information. Plain kind only, one invocation.
- [x] 3.4 The cache-size curve of D4. Run last, on the landed code (design D5).

## 4. Review and closing

- [x] 4.1 Final pass: keep the switch only if W turned out pack dependent; no dead code. The one-pass window has no W: switch, constant and the graded rank removed before the measurement that decided.
- [x] 4.2 `tests/model_gates.sh <Q4>`; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident `ab_bench.py --bitwise` against the segment start, with its record row. Bitwise is against `main` (the segment start differs in logit bits since earlier changes); the record row is the token-gated run against `91f225a`. Model gates also on Q2.
- [x] 4.3 `docs/SSD_STREAMING.md`: the eviction order, and the measured table if the streamed rates changed. The figures are a table of their own under "Eviction order": the older table was not taken with the page cache dropped at each run.
- [x] 4.4 `openspec validate 188-ssd-expert-eviction-recency --strict` passes.
- [x] 4.5 Report to the user in Italian. Land as one signed commit; delete `$SCR/c188/`; archive the change. The night executor's report goes to the session that started it, which reports to the user.
