# Qwen3.8 benchmarks

The C benchmarks isolate Metal scheduling and prefill variants. The scripts
measure server concurrency and plot repeatable results. Historical Qwen
checkpoint results live in `qwen38-checkpoints/`.

Use the same GGUF, prompt, context, thermal state, and command-line options for
before/after runs. Report medians and verify generated tokens before accepting a
speed improvement.

## A/B harness

`ab_bench.py` compares two build trees of this child on one GGUF and prints a
verdict that fits one screen:

```sh
git worktree add ../sf-q3-8flash-base main          # A: the baseline, once
python3 speed-bench/ab_bench.py --a ../sf-q3-8flash-base --b .
```

Pass trees, not binaries: the kernels are read from `metal/` in the working
directory when the process starts, so each build runs from its own tree. The
harness runs `make sf-q3-8flash-bench` in both trees first. `--a` and `--b` may
be the same tree; that A/A run measures the noise floor.

One invocation:

1. **Preflight.** It refuses (exit 2), naming the reason, unless the machine is
   on AC power, the thermal state is Nominal, the GPU is below `--max-gpu-temp`
   (60 °C), `/tmp/sf-q3-8flash.lock` is free and no other process has 8 GiB or
   more resident. After a run macOS keeps the state Heavy for a minute or two
   after the temperature has dropped; wait for Nominal.
2. **Warm-up.** One A and one B run per kind, untimed. Tokens are compared
   here, and with `--bitwise` every prefill and decode logits dump as well, so
   a correctness failure stops the harness within a minute.
3. **Preheat.** Untimed runs until `--preheat` seconds (210) after the first
   run started, at most half the budget. The M5 Max runs at about 1560 MHz for
   the first minute, throttles, and holds a stable plateau at about 1200-1300
   MHz from about 215-240 s; the timed rounds run there. The absolute numbers
   are therefore sustained throughput.
4. **Timed rounds.** A B B A quads per kind while the next one fits in
   `--budget` (480 s, at most 600). Pairs are (A1, B1) and (B2, A2); the verdict
   per metric is the median B/A ratio, with its range. A pair is dropped when
   one of its runs ran below `--min-freq-of-median` (0.90) of the timed runs'
   median GPU frequency: an external disturbance. The thermal state never drops
   a run.

Kinds (`--kinds`, default all three):

| Kind | Prompt | Frontiers | Tokens | Metrics |
|---|---|---|---|---|
| `plain` | `promessi_sposi.txt` | 8192, 8704, 10752 | 64 per frontier | prefill 8192 from empty, +512 and +2048 resumed; pooled decode |
| `mtp-code` | `rax.c` | 2048 | 128 | MTP decode, tokens per cycle, prefill with `--mtp`, cycle ms by tokens committed |
| `mtp-prose` | `promessi_sposi.txt` | 2048 | 128 | as `mtp-code` |

`--env KEY=VALUE` sets a variable for both builds (inherited `DS4_*` variables
are dropped), for example `--env DS4_QWEN4_MTP_DEPTH=3` to force the MTP depth.
`-m` selects another GGUF, such as the Q2 pack.

Exit status: 0 correct, with a verdict; 1 tokens or bits differ, or a run
failed; 2 refused or aborted (usage, tree, preflight, the GPU monitor stopped);
3 inconclusive (a headline metric has fewer than two pairs). Everything lands
in one directory (default `$TMPDIR/sf-q3-8flash-ab/<UTC time>`): `summary.txt`,
`samples.csv` (one row per timed run and frontier, with GPU frequency,
temperature, power and a token hash), `gpu.json` (raw `mactop` log), each
run's stderr and CSV, and the warm-up logits dumps.

Noise floor, A/A on the M5 Max plateau (2026-09-24): pooled plain decode and
MTP decode ±1-2% per pair; tokens per cycle exactly equal; prefill +512 and
+2048 about ±2-4%; prefill 8192, the first prefill of each process, up to about
±7%. A claim smaller than its metric's noise needs `--kinds <kind> --budget
600` for more pairs, and is read against this range.

Two references, two tools:

| What | Reference | Tool |
|---|---|---|
| Quality against the parent project | upstream at the child's merge-base | StarForge `tools/parity-check.sh sf-q3-8flash` |
| Bitwise identity of a step | this child's `main` or the previous step | `ab_bench.py --bitwise` |
| Speed of a step | this child's `main` or the previous step | `ab_bench.py` |

The summary ends with a row for [perf-record.md](perf-record.md), which keeps
where the performance work started and where it has got to.
