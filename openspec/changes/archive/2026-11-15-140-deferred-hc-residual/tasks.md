# Tasks

Starts from `main` with `90` landed. `<Q4>` is the child's
`qwen3.8-flash-next.gguf`; `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c140/`. Before each harness or section-time run,
wait until the thermal state is Nominal and the GPU is below 55 °C. Model runs
are strictly sequential; nothing else heavy is resident.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `make test-qwen4-kernels`, ending in
`all qwen4 kernel tests passed`; `make test-qwen4-prefill-reuse`.

## 1. Branch and references

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/140-deferred-hc-residual`. `git fetch upstream pull/1150/head`; save `git show ce6d991` to `$SCR/c140/`. Done (the branch already existed at `a543855`; the diff went to the session scratch `c140/ce6d991.diff`).
- [x] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it. Check `speed-bench/perf-record.md`: if the current segment has no start row after `90`, write it first with an A/A run on a worktree of the start commit. Done differently by the owner's decision: the "prev" tree is the main checkout, already built at `a543855`; the segment start row exists (segment 1 starts at `91f225a`, built worktree `seg1-91f225a`).
- [x] 1.3 Design D3: list every reader of the trunk R in the synced prefill path, and mark each eager, flushing, or to be added. Write the list to `$SCR/c140/readers.txt`. Done: thirteen readers listed (PLE gate/conv, both stream norms, steering FFN, ffn_out dump, head mixer, `30`'s priming, the T = 1 fusion, MTP/batch flows, vision); none unserved.

## 2. Step S1: the port

- [x] 2.1 Port `ce6d991` onto the synced kernels: the rows kernel, the wrapper, the pending-write state, the call sites, and the eager exceptions plus the readers from 1.3. Drop `04dbebe` (CUDA). Done. Child changes: the rows kernel combines and writes each element in the thread that norms it (upstream's version re-reads elements other threads wrote across a threadgroup-only barrier); the PLE-layer and steering flushes are not carried, since those layers already write eagerly; `qwen4_graph_moe_impl` takes `defer_hc` so `qwen4_graph_moe` keeps its callers.
- [x] 2.2 Port the byte-exact kernel cases into `tests/test_qwen4_kernels.c`. Run the step checks. Verify that the new cases run by name in the kernel test output. Done: 30 cases named `hc defer type=... reuse=0|1: byte-exact R/xn/inj ok` (f32/f16/q8, T = 3..256, against both the chunked and the reuse norm); `make -j8` no warnings, `make test -j8` rc 0 with every suite named, `all qwen4 kernel tests passed`, `test-qwen4-prefill-reuse` PASS.
- [x] 2.3 Step review: the diff and every function it touches. Fix what would make the step wrong or break a child rule. Done: the device-memory race above fixed; `hc_pending` zeroed with the graph and reset at the loop's start and end; shared-scratch graphs swap `inj`/`inj_alt` as the T = 1 fusion already does; the fallback (rows kernel refused) flushes then norms eagerly.

## 3. Correctness gates (design D1)

- [x] 3.1 `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q4> --bitwise --budget 600`: `PASS (tokens; bitwise)` on every kind. Done: `PASS (tokens; bitwise)` on plain, mtp-code and mtp-prose, 26 pairs.
- [x] 3.2 `python3 tests/test_qwen4_mtp_identity.py --model <Q4>`: every prompt and depth identical. Done inside `tests/model_gates.sh` (`PASS  mtp-identity (127 s)`, every prompt and depth SAME); the same run gave `PASS  mtp-limits`, `PASS  ds4_test` (the five known failures), `PASS  vision`, `PASS  host-paths`; the same five gates PASS on Q2 with the final build.
- [x] 3.3 Streamed against resident on this tree (`ab_bench.py --a . --b . --b-bench-arg --ssd-streaming --kinds plain`): token gate PASS. Done: `PASS (tokens)`, 5 pairs.
- [x] 3.4 Steering: the same `--dir-steering-file` run with an FFN scale on `../sf-q3-8flash-prev` and on `.`. Verify byte-identical stdout. Done: `qwen38-unit-probe.f32`, `--dir-steering-ffn 2`, 96 tokens: stdout byte-identical (508 bytes).

## 4. Verdict (design D2)

- [x] 4.1 Section times: `ab_bench.py --sections <HC and FFN groups> --a ../sf-q3-8flash-prev --b .` (ABBA), pooled with `ab_pool.py`. Kept if the ratio's CI lies below one at a prefill shape and above one at none. Record the figures in `$SCR/c140/steps.txt`. Done (groups hc_attn,hc_ffn,moe), two runs pooled (n = 12): prefill 8192 -5.2% (CI -9.2..-5.0), +512 -5.8% (CI -6.2..-5.2), +2048 -12.6% (CI -12.8..-12.4); decode +0.7% (CI +0.5..+0.8). The decode CI is above one although T = 1 dispatches the same kernels on both builds; four control runs traced it: not the inj/inj_alt orientation, not the Metal source, gone with the deferral switched off (-0.1%, CI -0.3..+0.3), and back (+0.3%, CI +0.1..+0.7) with the deferral off and only the rows pipeline created at the first prefill. It is pipeline placement, not the step's work; the whole decode pass moved +0.2% at most and the harness decode -0.2% (range -0.6..+0.2). Kept. Figures in the session scratch `c140/steps.txt`; the temporary switch and probe were removed.
- [x] 4.2 If kept: one harness run as the guard (bitwise, no throughput metric's pooled CI wholly below zero). If dropped: restore `main`'s files, record the figures, and go to 5.3. Done: the 3.1 run is the guard (it is the harness run with `--bitwise`): no metric's range wholly below zero; plain prefill +0.9/+1.3/+2.3%, MTP prefill 2048 +3.0% (+2.7..+3.2) and +2.8% (+2.7..+3.0), decode -0.2..+0.2%.

## 5. Review and closing

- [x] 5.1 Final pass over the touched region (AGENT.md, idiom, dead code). Decide on `DS4_QWEN4_NO_HC_DEFER` (design risks). Measure any refinement like a step. Done: `DS4_QWEN4_NO_HC_DEFER` removed (no measurement needs it; the A/B compares against `main`); forward declaration tidied. No GPU work changed, so no refinement measurement.
- [x] 5.2 `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout: `PARITY OK`. Then `ab_bench.py` against the current segment's start commit, appending the printed row to `speed-bench/perf-record.md` with step `perf/140-deferred-hc-residual`. Done: `PARITY OK (10 prompts)`. Against `91f225a` (24 pairs, `PASS (tokens)`): prefill 8192 +3.0%, +512 +3.2%, +2048 +5.4%, decode +6.0%, MTP prefill 2048 +4.5%; row appended.
- [x] 5.3 `docs/upstream-prs.md`: `ce6d991` to `adopt -> 140-deferred-hc-residual` with the figures, or `drop` with them; `04dbebe` stays `drop`. Done.
- [x] 5.4 `openspec validate 140-deferred-hc-residual --strict` passes. Done: valid.
- [x] 5.5 Report to the user in Italian. Commit only when the owner asks: one signed commit with the PR author as `Co-authored-by`.
  - Reported 2026-11-15 morning; the owner asked to commit and land 131, 101 and 140.
