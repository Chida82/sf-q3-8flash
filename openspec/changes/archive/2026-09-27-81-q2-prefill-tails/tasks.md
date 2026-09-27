# Tasks

`<Q4>` is the absolute path of `qwen3.8-flash-next.gguf` in the child
checkout. `<Q2>` is
`~/.cache/huggingface/hub/models--antirez--qwen3.8-flash-next-gguf/snapshots/d600fe1a43d2e1cdcadb85144ce3142f66f9eefe/Qwen3.8-Flash-Next-Q2.gguf`,
expanded to an absolute path. `$SCR` is `~/.sf/q3-8flash/scratch`, and this
change's files go in `$SCR/c81/`.

**Model runs are strictly sequential.** Nothing runs beside one: no other model
run, no test and no build. Before each run, wait until the thermal state is
Nominal. Give every run a fresh `--out` directory.

## 1. Branch and references

- [x] 1.1 Verify that `80-qwen-ssd-streaming` is on `main`, run `git config rerere.enabled true`, then `git switch -c perf/81-q2-prefill-tails`.
- [x] 1.2 Create the worktrees `../sf-q3-8flash-prev` at `main` and `../sf-q3-8flash-start` at `91f225a`, and build `sf-q3-8flash-bench` in each.

## 2. The gate and the clause

- [x] 2.1 Apply the gate of design D1. Run `make -j8` (no warnings), `make test -j8`, `make test-qwen4-kernels` (three Q2 `byte-exact mid/down nax=2` lines, `all qwen4 kernel tests passed`), `make test-qwen4-q2` and `python3 tests/test_ab_bench.py`.
- [x] 2.2 Add the clause of design D2 to `openspec/config.yaml`.
- [x] 2.3 Guard (design D3): `ab_bench.py --a ../sf-q3-8flash-prev --b . -m <Q2> --bitwise --budget 600 --out $SCR/c81/guard-q2`. Keep the step if a prefill metric gains at least 10% and no decode median is below -2%.

## 3. Closing

- [x] 3.1 Run one after the other: parity with `<Q2>`, then `<Q4>`, from the StarForge checkout; then `tests/test_qwen4_mtp_limits.py --model <Q2>`, then `<Q4>`.
- [x] 3.2 Record rows against `../sf-q3-8flash-start` for both packs, appended to Segment 1 with step `perf/81-q2-prefill-tails`.
- [x] 3.3 Re-measure the Q2 rows of `docs/SSD_STREAMING.md` (48 GB, and 40 GB with MTP), emulating memory only on the streamed B side.
- [x] 3.4 Update the `496b153` and #1056 lines of `docs/upstream-prs.md`.
- [x] 3.5 Final pass (design D7). Verify that `openspec validate 81-q2-prefill-tails --strict` passes.

## 4. Comparison with ds4 (design D6)

Run section 4 last, after section 3 has finished, never beside another run.

`<U>` is the upstream worktree that `tools/parity-check.sh` builds at the
child's merge-base (`$SF/upstream/.worktrees/<sha7>`, binaries `ds4` and
`ds4-bench`). Every run below is one process at a time, after the thermal
state is Nominal, in the order ds4, sf, sf, ds4 for each pack and case.

- [x] 4.1 Plain sweep, upstream's command, for `<Q2>` and `<Q4>`: `<bench> -m <model> --prompt-file speed-bench/promessi_sposi.txt --ctx-start 2048 --ctx-max 65536 --step-incr 2048 --gen-tokens 128`, with `<U>/ds4-bench` and `./sf-q3-8flash-bench`. Keep every CSV in `$SCR/c81/vs-ds4/`.
- [x] 4.2 Generation with and without MTP, for `<Q2>` and `<Q4>`, with `<U>/ds4` and `./sf-q3-8flash`: upstream's three Qwen cases (Hamlet 120, Fibonacci 400, Networking 256 tokens; `speed-bench/qwen38-checkpoints/README.md` in upstream), `--ctx 8192 --temp 0 --nothink`, once plain and once with `--mtp`. Record the `prefill: ... generation: ... t/s` line and the output text; verify that the plain text is identical between ds4 and sf.
- [x] 4.3 Build the table: for each pack, prefill and generation at contexts 2048, 16384, 32768 and 65536 from 4.1, and MTP and plain generation from 4.2 (mean of the three cases), each as ds4, sf, and sf's change against ds4 in percent. Each cell is the mean of the two runs per build. Where ds4 cannot run a case (for example MTP, if its binary refuses it), its cell stays empty and the row has no percentage.
- [x] 4.4 Add a short "Quality and performance" section to `README.md`: how token quality is checked (parity oracle against upstream, `--bitwise` A/B, byte-exact kernel tests against the CPU reference, MTP limits), how performance is measured (`speed-bench/ab_bench.py` and the performance record), and the table from 4.3 with the date, machine, commits and method.

## 5. Report

- [x] 5.1 Report to the user in Italian. Do not commit. On request, land one signed commit on `main` and remove the worktrees.
