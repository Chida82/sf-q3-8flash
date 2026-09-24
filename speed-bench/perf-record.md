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

Start commit: the `main` commit on which `20-perf-bench-harness` lands (the
first whose bench has `--mtp` and `--frontiers`). The first performance change
after it writes the start row on its own branch: an A/A run on a worktree of
that commit (`--a` and `--b` both the worktree).

| step | date | B commit | model | valid pairs | correctness | plain decode | plain prefill 8192 | plain prefill +512 | plain prefill +2048 | mtp-code decode | mtp-code tokens/cycle | mtp-code prefill 2048 | mtp-prose decode | mtp-prose tokens/cycle | mtp-prose prefill 2048 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
