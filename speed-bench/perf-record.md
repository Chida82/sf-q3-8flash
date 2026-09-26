# Performance record

Where the performance work on this child started, and where it has got to.
Each row is one `speed-bench/ab_bench.py` run, pasted from the `record row:`
line of its summary. A cell reads `B median (B/A)`: the candidate's absolute
median on the M5 Max thermal plateau, and its ratio to the segment's start
commit, measured in the same session. The ratio is the figure to read; the
absolute numbers depend on the room and the machine's power mode.

## Adding a row

1. `tools/parity-check.sh sf-q3-8flash <model>` from the StarForge checkout
   passes (quality against upstream at the merge-base).
2. `git worktree add ../sf-q3-8flash-start <start commit of the current segment>`.
3. `python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-start --b .` exits 0
   (tokens identical to the start, every headline metric with two pairs or
   more). Use `--bitwise` when the change claims bit-identical output.
4. Paste the printed row at the end of the current segment. The `step` cell is
   B's branch; the last row of a segment is where the work has got to.

## Segments

A segment starts with an A/A run on its start commit. A sync that changes
greedy output (for example a template fix) makes the token gate against the
old start commit fail by design; it then opens a new segment with a new start
row, and the previous segment's rows stay as they are.

### Segment 1

Start commit: `91f225a`, the `main` commit on which `20-perf-bench-harness`
landed (the first whose bench has `--mtp` and `--frontiers`). Its row is an
A/A run on a worktree of that commit (`--a` and `--b` both the worktree),
written by `30-mtp-cycle`.

| step | date | B commit | model | valid pairs | correctness | plain decode | plain prefill 8192 | plain prefill +512 | plain prefill +2048 | mtp-code decode | mtp-code tokens/cycle | mtp-code prefill 2048 | mtp-prose decode | mtp-prose tokens/cycle | mtp-prose prefill 2048 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| start (A/A) | 2026-09-24 | 91f225a | Qwen3.8-Flash-Next-Q4.gguf | 12 | PASS | 46.5 (+0.3%) | 1264.8 (+0.3%) | 875.9 (+0.1%) | 1023.1 (+0.2%) | 61.7 (-0.7%) | 1.83 (+0.0%) | 1288.5 (+0.6%) | 52.3 (-0.4%) | 1.51 (+0.0%) | 1277.6 (-3.2%) |
| perf/30-mtp-cycle | 2026-09-25 | fe126d3 | Qwen3.8-Flash-Next-Q4.gguf | 12 | PASS | 45.8 (+0.0%) | 1228.4 (-0.5%) | 831.8 (+0.0%) | 969.2 (-1.0%) | 68.5 (+12.4%) | 2.46 (+34.6%) | 1258.4 (-1.5%) | 51.1 (-2.4%) | 1.49 (-1.2%) | 1277.3 (-2.9%) |
| perf/40-dense-decode-kernels | 2026-09-25 | this row's commit | Qwen3.8-Flash-Next-Q4.gguf | 11 | PASS | 44.0 (+2.8%) | 982.4 (-3.6%) | 681.5 (+3.3%) | 822.7 (-4.2%) | 59.4 (+7.9%) | 2.46 (+34.6%) | 1026.7 (+3.0%) | 46.3 (+0.3%) | 1.49 (-1.2%) | 1038.9 (-2.0%) |
| perf/50-q4-expert-decode | 2026-09-25 | this row's commit | Qwen3.8-Flash-Next-Q4.gguf | 11 | PASS | 45.9 (+4.1%) | 1132.7 (+1.5%) | 678.5 (-4.9%) | 887.9 (-1.7%) | 65.4 (+16.2%) | 2.46 (+34.6%) | 1170.7 (+3.2%) | 48.6 (+0.5%) | 1.49 (-1.2%) | 1195.1 (-0.3%) |
| perf/60-q4-expert-prefill | 2026-09-25 | this row's commit | Qwen3.8-Flash-Next-Q4.gguf | 16 | PASS | 45.8 (+2.0%) | 1144.7 (+1.5%) | 798.3 (+8.9%) | 902.7 (+3.2%) | 64.8 (+13.1%) | 2.46 (+34.6%) | 1178.6 (+0.5%) | 49.4 (+0.4%) | 1.49 (-1.2%) | 1179.3 (+1.1%) |
| start (A/A, Q2) | 2026-09-25 | 91f225a | Qwen3.8-Flash-Next-Q2.gguf | 18 | PASS | 43.2 (-0.1%) | 1136.6 (+0.2%) | 699.7 (-0.3%) | 908.0 (+0.2%) | 57.3 (-0.3%) | 1.83 (+0.0%) | 1021.8 (-0.1%) | 44.4 (+0.3%) | 1.39 (+0.0%) | 1079.2 (-0.4%) |
| perf/70-q2-kernels-m5 | 2026-09-26 | this row's commit | Qwen3.8-Flash-Next-Q4.gguf | 17 | PASS | 45.4 (+2.3%) | 1173.1 (+4.2%) | 810.1 (+9.7%) | 927.5 (+3.8%) | 64.8 (+13.6%) | 2.46 (+34.6%) | 1190.7 (+4.5%) | 49.1 (+2.8%) | 1.49 (-1.2%) | 1207.1 (+3.0%) |
| perf/70-q2-kernels-m5 | 2026-09-26 | this row's commit | Qwen3.8-Flash-Next-Q2.gguf | 18 | PASS | 46.6 (+9.0%) | 1131.7 (+0.2%) | 688.5 (-1.0%) | 884.9 (-0.8%) | 62.8 (+10.3%) | 1.91 (+4.5%) | 1015.3 (-0.5%) | 49.5 (+12.4%) | 1.44 (+3.4%) | 1061.8 (-2.2%) |
