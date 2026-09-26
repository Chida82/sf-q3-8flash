# Spec Delta

## MODIFIED Requirements

### Requirement: Section-time mode
The harness SHALL offer a section-time mode, selected together with a list of
target stage groups (the groups `DS4_QWEN4_TIMING=2` reports, such as
`moe_mid` and `moe_down`). In this mode both builds SHALL run with the GPU
section profiler on, under the same preflight, warm-up, preheat, interleaved
schedule, budget and correctness gate as a throughput run. Only GPU times
SHALL be judged; throughput figures from profiled runs SHALL NOT be reported
as a speed verdict.

The mode SHALL judge these shapes of the selected kinds:
- every prefill chunk shape (for the plain kind: 8192 tokens from an empty
  context, then 512 and 2048 resumed);
- for the plain kind, a `decode` shape, from the profiler's single-token decode
  lines (each the mean GPU time per pass over 50 passes). A run's decode
  figure per group SHALL be the mean over all its single-token lines.

For each shape, the mode SHALL compute, per run, the GPU time of the target
groups divided by the GPU time of all other groups of the same chunk or
decode pass. It SHALL then compute, per valid A/B pair, B's ratio over A's.
The summary SHALL report per shape:
- A's and B's median target and untouched times;
- the median pair ratio with a bootstrap 95% CI;
- the median pair ratio of the whole chunk's or pass's GPU time.

Pairs dropped as disturbed SHALL be left out, as in the throughput verdict.
The raw per-run section times, per chunk and for decode, SHALL be written to
the output directory.

#### Scenario: Faster target sections
- **WHEN** B's `moe_mid` and `moe_down` take 3% less GPU time than A's while every other group is unchanged
- **THEN** the summary shows, per shape, a normalized ratio near 0.97 with its CI

#### Scenario: Clock drift between runs
- **WHEN** B's runs happen at a GPU clock 3% lower than A's and B changes no kernel
- **THEN** the normalized ratio stays near 1 while the whole-chunk ratio moves by about 3%

#### Scenario: Unknown group
- **WHEN** a target group is not one the profiler reports
- **THEN** the harness exits with status 2 before any run and names the group

#### Scenario: Missing section lines
- **WHEN** a profiled run's standard error lacks the chunk line of a shape the kind prefills
- **THEN** the run is a run failure (exit status 1) naming the kind and the shape

#### Scenario: Missing decode lines
- **WHEN** a profiled plain run's standard error has no single-token decode line
- **THEN** the run is a run failure (exit status 1) naming the kind and the `decode` shape

#### Scenario: Decode kernel step
- **WHEN** B's `moe_down` takes 2% less GPU time per decode pass than A's and nothing else changes
- **THEN** the `decode` row shows a normalized ratio near 0.98 for the target `moe_down`, with its CI

#### Scenario: Output still gated
- **WHEN** B's greedy tokens differ from A's in section-time mode
- **THEN** the verdict is FAIL exactly as in a throughput run
