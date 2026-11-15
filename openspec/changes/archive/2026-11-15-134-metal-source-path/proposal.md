# Proposal

## Why

`ds4_gpu_full_source()` in `ds4_metal.m` reads every kernel file
(`metal/*.metal`) at startup. For each file it tries `DS4_METAL_<NAME>_SOURCE`,
then `metal/<file>` and `./metal/<file>`, both relative to the **current
working directory**. A binary run from another tree therefore compiles that
tree's kernels against its own host code. That mixed build runs without an
error and can produce different tokens.

It already cost a wrong finding. In `97`, the 2026-11-14 queue ran the
`765e9a5` binaries from the main checkout. The "A" side was `765e9a5` host
code with `062d4c3` kernels; it generated different greedy text on the code
prompt. The reported halving of 3-token MTP cycles, and the verify-row deltas
attributed to the sync, both came from that mix. StarForge rule 18: prefer
removing a failure mode over describing it.

## What Changes

- Resolve `metal/<file>` against the directory of the running executable,
  then its parent. The parent covers binaries built under `tests/`, such as
  `tests/test_qwen4_kernels`. The current working directory is no longer
  searched.
- The per-file environment overrides stay. They are the deliberate way to run
  one swapped kernel file.
- The error when a file is missing names the paths it tried.

The four product binaries, `ds4_test`, the `tests/` binaries, `ab_bench.py`
and `sfctl`'s serve worktree all run binaries inside their own tree, so every
current use keeps working. Only the mixed case changes: it now loads the
binary's own kernels.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: kernel lookup only; output is identical for every same-tree run)

## Impact

- `ds4_metal.m` (`ds4_gpu_full_source`): one function diverges from
  upstream, marked at the site; rerere replays the resolution after the first
  sync.
- `docs/METAL.md` (where kernels are read from); `AGENTS.md` (one line in the
  traps list, stating the trap is removed).
