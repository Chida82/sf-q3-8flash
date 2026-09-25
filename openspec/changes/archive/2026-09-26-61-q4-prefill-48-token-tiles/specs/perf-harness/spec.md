# Spec Delta

## ADDED Requirements

### Requirement: Section-time mode
The harness SHALL offer a section-time mode, selected together with a list of
target stage groups (the groups `DS4_QWEN4_TIMING=2` reports, such as
`moe_mid` and `moe_down`). In this mode both builds SHALL run with the GPU
section profiler on, under the same preflight, warm-up, preheat, interleaved
schedule, budget and correctness gate as a throughput run. Only GPU times
SHALL be judged; throughput figures from profiled runs SHALL NOT be reported
as a speed verdict.

For every prefill chunk shape of the selected kinds (for the plain kind: 8192
tokens from an empty context, then 512 and 2048 resumed), the mode SHALL
compute, per run, the GPU time of the target groups divided by the GPU time of
all other groups of the same chunk. It SHALL then compute, per valid A/B pair,
B's ratio over A's. The summary SHALL report per shape:
- A's and B's median target and untouched times;
- the median pair ratio with a bootstrap 95% CI;
- the median pair ratio of the whole chunk's GPU time.

Pairs dropped as disturbed SHALL be left out, as in the throughput verdict.
The raw per-run, per-chunk section times SHALL be written to the output
directory.

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

#### Scenario: Output still gated
- **WHEN** B's greedy tokens differ from A's in section-time mode
- **THEN** the verdict is FAIL exactly as in a throughput run

### Requirement: Pooled verdict across invocations
The child SHALL provide a pooling tool that combines several harness
invocations of the same kind. For a throughput metric or a section-time shape,
it SHALL report the number of pooled pair ratios, their median and a bootstrap
95% CI. It SHALL leave out every pair the harness dropped as disturbed, and it
SHALL refuse output directories whose runs do not follow the harness's
interleaved order.

#### Scenario: Repeat run pooled
- **WHEN** a step's two invocations are pooled for prefill 8192
- **THEN** the tool prints one line with the pooled n, median and 95% CI over both invocations' valid pairs

#### Scenario: Dropped pair
- **WHEN** an invocation dropped one pair for a GPU clock below the floor
- **THEN** that pair's two ratios are not in the pooled set
