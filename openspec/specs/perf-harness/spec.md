# perf-harness Specification

## Purpose

Gives every performance change in this child a before/after verdict: a
thermally robust A/B comparison of two builds of the child on the same GGUF,
covering plain decode, prefill and built-in MTP, gated on token-identical (and,
on request, bit-exact) output.

## Requirements

### Requirement: Two build trees on one model
The harness SHALL take two build trees, A (baseline) and B (candidate), and
compare them on one GGUF. Each tree's benchmark binary SHALL run with that
tree's own Metal kernel sources, and SHALL be brought up to date with `make`
before any measurement. Both builds SHALL receive the same absolute model path
and the same prompt files. The same tree MAY be passed as A and B (an A/A run
measures the noise floor).

#### Scenario: Kernel change is seen by B only
- **WHEN** B differs from A only in a file under `metal/`
- **THEN** A's runs use A's `metal/` sources and B's runs use B's

#### Scenario: Stale binary
- **WHEN** a tree's sources are newer than its benchmark binary
- **THEN** the harness rebuilds that binary before preflight

#### Scenario: Not a build tree
- **WHEN** a path given as A or B has no `metal/` directory or no Makefile
- **THEN** the harness exits with status 2 and names the path

#### Scenario: Q2 model
- **WHEN** the user passes `-m` with the Q2 GGUF
- **THEN** both builds run on that file and the summary names it

### Requirement: Inherited toggles do not leak
The harness SHALL remove every inherited `DS4_*` environment variable from the
benchmark processes. Variables passed explicitly to the harness SHALL be given
to both builds and listed in the summary.

#### Scenario: Exported kernel override
- **WHEN** the shell exports `DS4_METAL_QWEN4_SOURCE`
- **THEN** neither build sees it

#### Scenario: Forced MTP depth
- **WHEN** the user passes `DS4_QWEN4_MTP_DEPTH=3` to the harness
- **THEN** both builds run with it and the summary lists it

### Requirement: Preflight refusal
Before any model process starts, the harness SHALL refuse to run, with exit
status 2 and the failed condition named, unless all of these hold:
- the machine is on AC power (a machine without a battery counts as on AC);
- the thermal state is Nominal;
- GPU temperature is below a configurable threshold;
- no process holds this child's instance lock and no other process has a
  resident set of 8 GiB or more;
- `mactop` is installed and returns a reading.

#### Scenario: On battery
- **WHEN** the charger is disconnected
- **THEN** the harness exits 2 with a message naming AC power, and no model process starts

#### Scenario: Another model is resident
- **WHEN** another child's server holds a 60 GiB resident set
- **THEN** the harness exits 2 and names that process's PID and command

#### Scenario: Missing monitor
- **WHEN** `mactop` is not on `PATH`
- **THEN** the harness exits 2 saying `mactop` is required; it does not run without the GPU log

### Requirement: One model process at a time
The harness SHALL run benchmark processes strictly one after another, never two
at once.

#### Scenario: Serial schedule
- **WHEN** a run finishes
- **THEN** the next run starts only after the previous process has exited

### Requirement: Untimed warm-up
Before any timed run, the harness SHALL run every selected run kind once for
each build without recording its throughput, so that the resident weights are
paged in. The warm-up results SHALL feed the correctness gate. If the warm-up
already shows a correctness mismatch, the harness SHALL stop before the timed
rounds.

#### Scenario: Fail fast
- **WHEN** A's and B's warm-up token streams differ
- **THEN** the harness writes the mismatch, skips the timed rounds and exits with status 1

### Requirement: Interleaved timed rounds
For each run kind the harness SHALL schedule timed runs in quads A B B A, so
that thermal drift weighs on both builds equally, and SHALL form one pair from
each half of a quad: (A1, B1) and (B2, A2). The verdict for a metric SHALL be
the median over valid pairs of the B/A ratio.

#### Scenario: One quad
- **WHEN** one quad of the plain kind completes
- **THEN** the plain metrics report the median of two B/A ratios

### Requirement: Wall-clock budget
A harness invocation SHALL finish within its time budget, warm-up included. The
budget SHALL default to less than 10 minutes, and a budget above 600 seconds
SHALL be refused with status 2. The harness SHALL start another quad only if
its predicted duration, from the durations measured so far, fits in the
remaining budget. If fewer than two valid pairs exist for any reported metric,
the verdict SHALL be inconclusive (exit status 3), not a ratio.

#### Scenario: Budget reached
- **WHEN** the next quad would end after the budget
- **THEN** the harness stops scheduling runs and writes the summary from the pairs it has

#### Scenario: Too few pairs
- **WHEN** the budget fitted no quad of the plain kind, or disturbances left one pair
- **THEN** the summary marks plain decode inconclusive and the harness exits 3

### Requirement: GPU log and thermal preheat
While the harness runs, it SHALL log GPU frequency, GPU temperature, GPU power,
GPU activity and thermal state at about 1 Hz. Between the warm-up and the timed
rounds it SHALL keep the machine under load with untimed runs until a
configurable preheat time has passed since the first run started (default
210 seconds, at most half the budget), so that on a laptop the timed rounds run
on the throttled thermal plateau rather than across the throttle.

The thermal state SHALL NOT exclude a run or a pair. A pair SHALL be excluded
only when one of its runs has a median active GPU frequency below a
configurable fraction (default 0.90) of the median over the invocation's timed
runs, the mark of an external disturbance. The summary SHALL report the GPU
frequency range and the thermal states of the timed runs, so a reader can see
which regime the numbers belong to. The monitor
stopping before the last run SHALL abort the harness, not be ignored.

#### Scenario: Timed rounds start after the preheat
- **WHEN** the warm-up ends 40 seconds after the first run started and the preheat is 210 seconds
- **THEN** untimed runs continue until 210 seconds have passed, and only then does the first quad start

#### Scenario: Preheat capped by the budget
- **WHEN** the budget is 300 seconds and the preheat is 210 seconds
- **THEN** the preheat ends 150 seconds into the invocation

#### Scenario: Throttled runs are kept
- **WHEN** every timed run shows the thermal state Heavy and runs between 1207 and 1350 MHz
- **THEN** all pairs count and the summary reports Heavy

#### Scenario: External disturbance
- **WHEN** the timed runs' median frequency is 1308 MHz and one run ran at 932 MHz
- **THEN** that run's pair is excluded, both runs show the reason, and the quad's other pair is kept

#### Scenario: Monitor stops
- **WHEN** `mactop` exits before the last run
- **THEN** the harness aborts with status 2

### Requirement: Metric set
The harness SHALL measure these run kinds, each selectable:
- **plain**: prefill tok/s for 8192 new tokens from an empty context, then 512
  and 2048 new tokens resumed on top of it; plain greedy decode tok/s;
- **MTP, code prompt** and **MTP, prose prompt**: built-in MTP greedy decode
  tok/s, committed tokens per cycle, the number and mean duration of cycles by
  tokens committed (1, 2 or 3), and prefill tok/s with MTP on.

#### Scenario: Default run
- **WHEN** the harness runs with no kind selection
- **THEN** the summary reports every metric above for both MTP prompts

#### Scenario: Prefill-only change
- **WHEN** the user selects only the plain kind
- **THEN** no MTP run starts and the freed budget goes to more plain quads

### Requirement: Correctness gate
The harness SHALL compare the generated token ids of A and B for every run kind
and frontier, and SHALL also compare A's runs with each other. Any difference
SHALL make the verdict FAIL (exit status 1) regardless of speed, naming the run
kind, the frontier and the first differing position. In bitwise mode the
harness SHALL additionally compare, bit-exact, the logits A and B produce at
every prefill frontier and after the last decoded token of each frontier.

#### Scenario: Token drift
- **WHEN** B's plain decode after frontier 8704 differs from A's at token 57
- **THEN** the summary says FAIL: plain, frontier 8704, position 57, and the harness exits 1

#### Scenario: Nondeterministic baseline
- **WHEN** two A runs of the same kind produce different tokens
- **THEN** the summary says the baseline is nondeterministic and the harness exits 1

#### Scenario: Bitwise claim broken
- **WHEN** bitwise mode is on and one logit at the 8192 frontier differs in its last bit while tokens match
- **THEN** the verdict is FAIL and names the frontier and the vocabulary index

### Requirement: Output
Every invocation SHALL write, into one output directory: a raw CSV with one row
per timed run and frontier (build, kind, frontier, metrics, GPU frequency
median, flag and reason, token hash); the raw GPU log; each run's standard
error; and a summary that fits one screen and is also printed. The summary
SHALL name both trees with their commit and whether they had uncommitted
changes, the model file, the device, the budget used, the preheat time, the GPU frequency
range and thermal states of the timed runs, the number of valid and dropped
pairs, the correctness verdict and, per metric, the A and
B medians, the median B/A ratio and the range of ratios.

#### Scenario: Citable verdict
- **WHEN** a run completes
- **THEN** the summary alone is enough to paste into a commit message as the change's evidence

### Requirement: Record row
The summary SHALL end with one Markdown table row, ready to paste into the
performance record, whose header the harness also defines. The row SHALL
hold the step (B's branch), the date, B's commit, the model file,
the number of valid pairs, the correctness verdict and, for every reported
metric, B's absolute median together with the median B/A ratio. Metrics not
measured in the invocation SHALL appear as empty cells, so every row has the
same columns.

#### Scenario: Cumulative row
- **WHEN** A is the start commit and B is the final tree of `30-mtp-cycle`
- **THEN** the row shows B's tok/s per metric and the ratio to the start commit

#### Scenario: Subset of kinds
- **WHEN** only the plain kind was run
- **THEN** the MTP cells of the row are empty and the plain cells are filled

### Requirement: Benchmark MTP mode
`sf-q3-8flash-bench --mtp` SHALL decode with built-in MTP greedy speculation
and SHALL print, per frontier, the number of MTP cycles, the tokens they
committed, and the count and mean duration of cycles by tokens committed. It
SHALL exit with an error when MTP cannot be enabled (CPU backend, or a model
without an MTP layer) and when combined with `--teacher-forced-decode`, since a
speculative cycle chooses its own tokens.

#### Scenario: MTP decode
- **WHEN** the bench runs with `--mtp` on the Q4 GGUF
- **THEN** each frontier's decode goes through MTP cycles and the per-frontier MTP line is printed

#### Scenario: Incompatible options
- **WHEN** the bench is given `--mtp --teacher-forced-decode`
- **THEN** it exits with status 2 before opening the model

### Requirement: Benchmark frontier list
`sf-q3-8flash-bench --frontiers N1,N2,...` SHALL measure prefill at exactly the
listed context frontiers, each timed interval being the tokens between one
frontier and the previous one (the first from an empty context). The list SHALL
be strictly increasing and positive, or the bench exits with status 2.

#### Scenario: Resumed suffixes
- **WHEN** the bench runs with `--frontiers 8192,8704,10752`
- **THEN** it reports prefill for 8192, 512 and 2048 new tokens, in that order

#### Scenario: Bad list
- **WHEN** the bench is given `--frontiers 2048,512`
- **THEN** it exits with status 2 naming the option

### Requirement: Benchmark token and logit evidence
With `--show-output`, the bench SHALL print the generated token ids of each
frontier. With `--dump-frontier-logits-dir`, it SHALL write, besides the
existing logits after each prefill frontier, the logits after the last decoded
token of that frontier, in the same format, with every float32 value written so
that it reads back to the same bits.

#### Scenario: Decode logits file
- **WHEN** the bench runs with `--dump-frontier-logits-dir D --frontiers 8192`
- **THEN** `D` holds a prefill logits file and a decode logits file for frontier 8192
