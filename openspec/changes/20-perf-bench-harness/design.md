# Design

## Context

See proposal.md (Why) and specs/perf-harness/spec.md (requirements). Facts
from the code that shape the approach:

- **Kernels load from the working directory.** `ds4_gpu_full_source`
  (`ds4_metal.m`) reads `metal/*.metal` at run time, from the path in
  `DS4_METAL_*_SOURCE` if set, else `metal/<file>` relative to the cwd. A
  binary run from the wrong tree silently uses that tree's kernels, so an A/B
  of a kernel change run from one directory compares B against B.
- **The bench already carries the speculative loop.** `ds4_bench.c` keeps the
  whole `ds4_session_eval_speculative_argmax` branch, including per-call timing
  under `DS4_BENCH_SPEC_TRACE`. Only its switch is gone:
  `const bool speculative = false; /* sf-ablate(specdec) ... */`. Upstream's
  line is `cfg.dspark && ds4_engine_mtp_draft_tokens(engine) > 1`. For Qwen,
  `ds4_engine_mtp_draft_tokens` returns 2 when `engine.glm_mtp` is set on a
  non-CPU backend, and the speculative entry routes to
  `ds4_session_qwen4_spec_cycle`.
- **The help already lies.** `ds4_help.c` prints `--mtp` for every tool,
  including the bench, which rejects it today as an unknown option.
- **`--mtp-timing` gives counts, not times.** It prints verify cycles and
  accepted drafts once, when the session is freed. The bench's
  `DS4_BENCH_SPEC_TRACE` gives mean ms per call by tokens committed, but it is
  cumulative over the process and printed every 32 calls, so the tail is lost.
- **Frontiers are arithmetic or geometric.** `--ctx-start` plus `--step-incr`
  or `--step-mul` cannot produce the 8192 / +512 / +2048 intervals the metric
  set needs from one process.
- **Logit dumps already exist for prefill.** `--dump-frontier-logits-dir`
  writes the logits after each prefill frontier, as `%.9g`, which round-trips
  float32, outside both timing windows. Nothing dumps after decode, so a
  decode-kernel change (`40`, `50`) has no bitwise evidence.
- **The CSV header is read by tools.** `speed-bench/plot_speed.py` requires
  `ctx_tokens`, `prefill_tps`, `gen_tps`; the header is upstream's.
- **The bench takes the instance lock** (`ds4_acquire_instance_lock`,
  `/tmp/sf-q3-8flash.lock`), so a second child model process fails, but a
  resident model of another child (different lock) does not.
- **`mactop` 2.1.5 is installed** and, without sudo, `--headless --format csv`
  streams one line per sample with GPU frequency, activity, power and
  temperature, thermal state and AC power. JSON mode gives the same fields
  (`soc_metrics.gpu_freq_mhz`, `soc_metrics.gpu_temp`, `thermal_state`,
  `battery.on_ac_power`).
- **No upstream commit is adopted.** Nothing in `docs/upstream-prs.md` changes.
  The registry's #1062 `68cd651` session-concurrency benchmark (already in main
  as `speed-bench/session_concurrency_bench.c`) measures a different thing:
  many sessions, not two builds.

## Goals / Non-Goals

**Goals:**
- One command that produces a citable A/B verdict for the changes numbered
  30-80, including MTP.
- Make the wrong-kernels trap unreachable instead of documenting it.
- Bench changes stay small and additive, so the sync cost is a few known
  sites.
- A record of where the plan starts and where it gets to, in absolute numbers
  and as a ratio measured in the same session (D14).

**Non-Goals:**
- Comparison with upstream inside the harness: StarForge's
  `tools/parity-check.sh` is the quality reference (D13).
- Server, batched-session or concurrency throughput.
- CPU backend, TP, pipeline or SSD streaming runs (`80` adds its own mode).
- Speed pass/fail thresholds: the harness reports ratios; each change states
  what gain it needs.
- Plots, history, or statistics beyond median and range.
- Creating worktrees from git refs: the user passes directories.

## Decisions

### D1. Build inputs are trees, and each binary runs from its own tree

`--a DIR --b DIR`. The harness runs `make -C DIR sf-q3-8flash-bench`, then runs
`DIR/sf-q3-8flash-bench` with `cwd=DIR`. It records `git -C DIR rev-parse
--short HEAD` and whether `git status --porcelain` is empty. Building runs
before preflight so that compile heat is seen by the temperature check.

Alternative: take two binary paths. Rejected: the binary does not carry its
kernels, so a binary path cannot identify a build.

### D2. MTP is measured in the bench, not the CLI

Add `--mtp` to `sf-q3-8flash-bench`, setting `opt.glm_mtp`. Replace the
`sf-ablate(specdec)` constant with `cfg.mtp && ds4_engine_mtp_draft_tokens(engine)
> 1`, and fail when `--mtp` was asked but did not engage, as upstream does for
DSpark. Reject `--mtp` with `--teacher-forced-decode` at parse time. The two
error strings in the loop that say "DSpark decode" are changed to "MTP decode":
in this child that loop only runs MTP.

Alternative: drive `sf-q3-8flash --mtp --mtp-timing`. Rejected: no frontier
control, a chat template in the way, timing only as end-of-process counts, and
model load inside the measured wall time. The bench already has timing
windows, snapshot restore, CSV and logit dumps.

### D3. MTP statistics: one stderr line per frontier

In MTP mode the bench counts, per frontier, calls and committed tokens, and for
k = 1..3 the number of calls that committed k tokens and their total time. It
prints `ds4-bench: mtp[ctx=N] cycles=C tokens=T k1=n/ms k2=n/ms k3=n/ms` after
the frontier's decode. Tokens per cycle is T/C. The upstream
`DS4_BENCH_SPEC_TRACE` block stays untouched.

Alternative: new CSV columns. Rejected: the header is upstream's and read by
`plot_speed.py`; a stderr line only in MTP mode leaves the CSV and its sync
alone.

Cycles by tokens committed are cycles by outcome, not by depth. The depth split
`30-mtp-cycle` needs (`c2`, `c3`) comes from forcing `DS4_QWEN4_MTP_DEPTH=2` or
`=3` through the harness (D8), which `qwen4_spec_depth` reads per cycle.

### D4. `--frontiers N1,N2,...`

The bench parses a strictly increasing list and walks it instead of
`next_frontier`. `ctx_start` and `ctx_max` become its first and last entries,
so the existing prompt-length and `--ctx-alloc` checks apply unchanged. It
overrides `--ctx-start`, `--ctx-max`, `--step-incr` and `--step-mul`.

Plain kind: `--frontiers 8192,8704,10752`, which gives 8192 new tokens from
empty (one full 8192-row prefill chunk), then 512 and 2048 resumed.

Alternative: separate processes per point. Rejected: an extra model load per
point, and the short points would start from an empty context instead of on
top of a resident prefix, which is the disk-KV-resume shape they stand for.

### D5. Token evidence: ids under `--show-output`

The bench already buffers the frontier's token ids for `--show-output`. It
prints them as one more line: `ds4-bench: gen[ctx=N] token ids: ...`. The
harness always passes `--show-output`, hashes each id list (SHA-256), stores
the hash in the samples CSV and keeps the lists for the first-difference
report.

### D6. Logit evidence: dump after decode as well

After each frontier's generation loop and before the restore, the bench writes
the session logits to `frontier_%06d.decode.logits.json` through the existing
writer (a filename suffix parameter). The harness does not parse the dumps
itself: it calls `validate_dump` from
`gguf-tools/quality-testing/compare_frontier_logits.py`, which already checks a
bench dump strictly (exact fields, canonical `%.9g` float32 spelling, signed
zero, argmax consistency, no non-finite values) and returns the float32 words.
The harness compares the words of A and B and reports the first differing
vocabulary index. That script's directory-level comparison accepts only the
prefill files, so the harness walks the files itself; the per-file validator
works unchanged on the decode files, whose metadata has the same shape.

Dumps run only in the warm-up runs and only with `--bitwise`. They sit outside
the timing windows, but they add disk writes of about 2-3 MB per file.

### D7. Schedule and budget

1. Build both trees (D1), then preflight (D9), then start the GPU monitor
   (D10).
2. Warm-up: for each selected kind, one A run and one B run, with
   `--dump-frontier-logits-dir` when bitwise. The first run pages in the
   weights. Correctness is checked here; a mismatch stops the harness (exit 1).
3. Preheat (D10): untimed runs of the first kind, alternating A and B, until
   `--preheat` seconds after the first run started (at most half the budget).
   Their tokens are checked too.
4. Timed rounds: for each kind in turn, a quad A B B A, then the next kind,
   then the next set of quads. Before each quad the harness predicts its
   duration from the latest measured duration of each (build, kind), plus 10%,
   and starts it only if it ends within the budget.
5. Summary.

Defaults: budget 480 s (maximum 600), kinds `plain,mtp-code,mtp-prose`,
plain `--gen-tokens 64`, MTP `--frontiers 2048 --gen-tokens 128`. Measured on
the target machine (first A/A run, with 128 and 256 tokens): plain run 17-20 s,
MTP run 7-8 s, warm-up about 65 s, plateau about 215-240 s after the start of
load. The shorter defaults bring a quad set of all three kinds to about
100-110 s, so the default budget gives two quad sets after the plateau, four
pairs per metric; `--budget 600` gives three or four sets, and `--kinds plain`
about twice as many plain pairs.

Pairs come only from adjacent runs of the same kind (A1 B1, B2 A2), so the two
runs of a pair are about 20 s apart.

Alternative: fixed cool-down waits between runs (StarForge
`speed-compare.sh` waits 180 s), to measure always cold. Rejected: two or three
pairs fit in ten minutes. Measuring on the plateau with interleaving is what
the budget allows (D10).

### D8. Environment

Every inherited `DS4_*` variable is dropped. `--env KEY=VALUE` (repeatable)
sets a variable for both builds and appears in the summary. There is no
per-build variable: a difference between A and B must be in the tree, where
the summary's commit records it.

### D9. Preflight

- AC power and thermal state from one `mactop` sample: `battery.on_ac_power`,
  or `battery.present == false` for a desktop; `thermal_state == "Nominal"`.
- GPU temperature below `--max-gpu-temp` (default 60 °C; this machine idles
  near 39 °C).
- Instance lock: the harness tries `fcntl.flock(LOCK_EX | LOCK_NB)` on
  `/tmp/sf-q3-8flash.lock` and releases it at once.
- Other resident models: `ps -axo pid=,rss=,comm=`, any process at or above
  8 GiB RSS, except the harness itself.

Every failure names its condition and exits 2. There is no override flag: a
reading taken on battery or while hot is not a verdict.

### D10. GPU monitor and thermal preheat

`mactop --headless --interval 1000 --count 0` runs for the whole invocation,
writing `gpu.json`: one JSON object per line, prefixed by `[` or `,`. JSON
rather than `--format csv`, because the CSV has no GPU power column. Fields are
looked up by key (`soc_metrics.gpu_freq_mhz`, `gpu_active`, `gpu_power`,
`gpu_temp`, `thermal_state`), and a missing key aborts with the mactop version.
Only the line being written when mactop is stopped may be partial.

What the first A/A run showed on the M5 Max (all numbers from its `gpu.json`
and `samples.csv`):

| Phase | Time from first load | GPU | Plain decode |
|---|---|---|---|
| cold | 0-90 s | about 1560-1620 MHz, 47 W, temperature climbing to 96 °C, Nominal | 54 tok/s |
| throttle | 90-215 s | frequency falls, thermal state Moderate then Heavy | falling |
| plateau | from about 215-240 s | about 1190-1270 MHz, about 20-25 W, 71-78 °C, Heavy | about 45.5 tok/s |

On the plateau, A/A pairs agree within about ±1% on plain decode and ±2-4% on
prefill and MTP decode. The pairs that lie are the ones that straddle the
throttle: run 9 (B, cold) against run 10 (A, throttling) reads +12% on an A/A.

Two ways to find the plateau from the log failed on the second A/A run:

- **Automatic plateau detection** (last 30 s matching the 30 s before in
  frequency, temperature and thermal state) fired at 101 s. Just before the
  throttle the state stays Nominal, the temperature sits flat at the 95 °C
  ceiling and the frequency is flat, which looks exactly like a plateau.
- **Dropping pairs by frequency gap** (runs more than 3% apart in median
  active GPU frequency) dropped 13 of 20 pairs and kept bad ones. mactop's
  frequency does not predict a pair's error: run 23/24 differed by -4.0% in
  frequency and +6.6% in prefill; the transition pair 11/12 differed by only
  1.9% in frequency and by -7.7% in prefill; normalising throughput by
  frequency made the ratios worse.

So:

- **Fixed preheat.** After the warm-up, untimed runs of the first kind,
  alternating A and B, continue until `--preheat` seconds (default 210) after
  the first run started, at most half the budget. 210 s is this machine's
  measured plateau start; it is a calibration knob, not a law.
- **No rejection by thermal state, and frequency only against disturbances.**
  On a laptop the plateau is Heavy, and mactop's frequency does not predict a
  pair's error at the few-percent level. It does show an external disturbance:
  in the third A/A run, runs 34-36 fell to 932-1123 MHz and 17-19 W against a
  1308 MHz median, and MTP decode fell from about 62 to 49 tok/s. So a pair is
  dropped only when one of its runs is below `--min-freq-of-median` (default
  0.90) of the median over the timed runs; both runs carry the reason. On the
  three A/A logs this drops exactly those three runs' pairs and nothing on the
  other two (their slowest runs sat at 93-95% of the median). Thermal states
  and the frequency range are reported. The absolute numbers are sustained
  throughput, which is also what a long generation sees.
- A run with fewer than two active lines is marked `unjudged` in the summary.

Measured noise on the plateau, A/A: in the second run, plain and MTP decode
within about ±1% per pair; in the third, about ±2% outside the disturbance.
Tokens per cycle are exactly equal (deterministic). Prefill +512 and +2048
vary about ±2-4% per pair, and prefill 8192, the first prefill of each process,
up to about ±7%. The prefill noise is not
explained by GPU frequency. Candidate causes, not verified: first-use costs of
the first prefill in a process, and the BF16 n-gram rows read from SSD with
`F_NOCACHE` on every prefill.

Per-run rather than per-frontier measurement: `mactop` timestamps have
one-second resolution, and one run takes 6-20 s.

### D11. Prompts and model

- Plain and MTP prose: `speed-bench/promessi_sposi.txt` (1.3 MB).
- MTP code: `rax.c` (vendored, stable, about 105 KB).
- Both are raw `--prompt-file` text, so the continuation is prose or C.

Paths are resolved from the harness's own checkout to absolute paths and
passed to both builds. `-m` defaults to the realpath of that checkout's
`qwen3.8-flash-next.gguf`, so a worktree without the symlink still uses the
same file.

### D12. Implementation form

The harness is one Python 3 stdlib script, `speed-bench/ab_bench.py`, next to
the existing `serve_concurrency_bench.py`: subprocess, csv, statistics, fcntl,
hashlib. Its pure parts are covered by `tests/test_ab_bench.py` with synthetic
data, in the style of `tests/test_serve_concurrency_bench.py`: pairing and
median, throttle flags, budget prediction, token and logit comparison, log
parsing. Like that test, it is run directly, not from `make test`, which keeps
the Makefile's `test:` block untouched.

Exit status: 0 correct, with a verdict; 1 correctness failure; 2 refused
(usage, tree, preflight); 3 inconclusive.

### D13. Two references: quality against upstream, speed against the child

| What | Reference | Tool |
|---|---|---|
| Quality against the parent project | upstream at the child's merge-base | `tools/parity-check.sh sf-q3-8flash` |
| Bitwise identity of a step | the child's `main` or the previous step | `ab_bench.py --bitwise` |
| Speed of a step | the child's `main` or the previous step | `ab_bench.py` |

`parity-check.sh` already does what a quality reference needs. It builds
upstream at `git merge-base` (today `0aaea5a`, not upstream's HEAD `8db1d1d`,
whose newer commits would show false differences) in its own worktree, runs
each binary from its own tree, and requires identical greedy output on the
child's 10 parity prompts, including one with `--mtp` and one with steering.
Upstream's bench cannot be the bitwise or MTP reference: it has no Qwen MTP
mode, no `--frontiers`, no token ids and no decode logits dump.

The two references chain: `main` is token-identical to upstream (parity), and
a step is identical to `main` (harness), so the step is token-identical to
upstream. Parity compares tokens only; whether `main`'s logits are bit-identical
to upstream's is not established and the chain does not need it.

Situation 0 is one `parity-check.sh` run on `main` before any measurement. If
it fails, `main` is not a valid reference and the harness is not built on it.
The change ends with a second parity run, which also shows that the bench
changes do not touch CLI output.

### D14. Performance record

`speed-bench/perf-record.md` answers "where did the plan start and where did
it get to". It is a table, one row per measurement, in the format the harness
prints (spec "Record row").

- **Start commit**: the `main` commit on which this change lands. An earlier
  commit cannot be measured, because its bench has neither `--mtp` nor
  `--frontiers`. This change touches only the bench, the help text and tools,
  not the engine or the kernels, so that commit's speed is the speed before the
  plan.
- **Start row**: an A/A run on a worktree of the start commit, written by the
  first performance change after this one, on that change's own branch, with
  the start commit's SHA. Nothing is edited on `main`, and this change needs no
  step after its merge. The SHA records what was measured,
  like the head SHAs in `docs/upstream-prs.md`.
- **Later rows**: every later performance change ends with an A/B where A is a
  worktree of the start commit and B is the change's final tree, and appends
  the printed row. The ratio in each row is cumulative, and the last row is
  where the plan got to. The rule goes into the `context` of
  `openspec/config.yaml`, which every proposal, design and task list reads.
- **Segments**: a sync that legitimately changes greedy output (for example
  `f5e419d`, marked `next sync` in the registry) makes the token gate against
  the start commit fail. The record then opens a new segment with a new start
  row, keeping the previous segment's rows.

Alternative: store the start's absolute numbers once and compare later runs
against them. Rejected: thermal drift between sessions (5-15% reported in
#1062) exceeds most expected gains. The absolute numbers stay in the record as
information; the ratio, measured in the same session, is the figure.

## Risks / Trade-offs

- [Two pairs per metric is a weak median] → The summary prints n and the ratio
  range. Changes that claim under about 2% select only their kinds to fit more
  quads, and an A/A run records the noise floor in the README.
- [Prefill varies ±2-4% per pair on the plateau, and up to ±7% for the first
  prefill of a process] → A prefill claim under about 2-3% needs
  `--kinds plain --budget 600` and is read against the A/A range in the README.
- [The plateau depends on the room and the machine's power mode] → The summary
  prints the frequency range and thermal states; runs meant to be compared
  should use the same power mode. High Power Mode (`pmset powermode 2`) was not
  tried.
- [Plain decode excludes EOS; an MTP cycle may commit it and end the frontier
  early] → Same for A and B, so the gate and the ratios are unaffected. The
  tok/s figure uses the tokens actually generated.
- [mactop output changes between versions] → Header-name lookup, a loud abort
  on a missing column, and the mactop version in the summary.
- [Session payload above the bench's 1 GiB snapshot limit makes the bench
  replay prefixes] → Replay sits outside the timing windows; the budget
  predictor uses measured durations, so it adapts. The first model-backed task
  records whether 10752 tokens snapshot or replay.
- [The page cache is evicted between runs by other apps] → Preflight refuses
  large residents. A run that pages in shows up as a slow run, and its pair
  ratio as an outlier inside the reported range.
- [Sync conflicts in `ds4_bench.c`] → Four sites: the `specdec` constant (it
  already conflicts, since it is an ablation site; the recorded rerere
  resolution must be redone once), the option parser, the per-frontier stats
  block after the decode loop, and the `--show-output` block. All are additive
  except the constant.
- [Warm-up correctness catches only what one run shows] → Every timed run's
  tokens are also compared, so a nondeterministic or late drift still fails
  the gate.
- [A later change adds a bench flag the start commit's bench lacks] → A runs
  its own tree's bench, so the harness uses only flags present at the start
  commit. A metric that needs a newer flag is measured against the previous
  step, not against the start, and its record cell stays empty.
- [A sync changes greedy output] → New record segment (D14), not a failed row.

## Migration Plan

Additive only: new bench flags, a new script and a test. Existing bench
invocations and CSV output are unchanged. Rollback is a revert of the branch.

## Open Questions

- Defaults for `--max-gpu-temp` (60 °C) and `--preheat` (210 s) are this
  machine's values. Another machine or power mode may need a different preheat;
  the knob stays and the README records how it was chosen.
- The source of the prefill noise (first-use costs or SSD n-gram reads) is not
  known. Finding it could let prefill claims under 2% be judged; it does not
  change the harness.
- Cold page-in time of the Q4 weights: if the first warm-up run alone takes
  more than about 90 s, the default budget leaves one quad set. Measured in the
  validation task, and the default budget is adjusted within the 600 s cap.
