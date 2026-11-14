# Proposal

## Why

The sync to `b3f5018` (`90-upstream-sync-b3f5018`) brings 267 upstream
commits. Many add code for models and backends this child removed (DeepSeek
V4.1 decode helpers, GLM sparse-boundary and MTP bridges, Spark and ROCm
plumbing, CUDA Qwen kernels) inside files the child keeps. Merges do not
conflict on additions, so this code lands silently: SYNC.md step 5 removes
only what is obvious at merge time. The child exists to be cheap to read
(StarForge rule 16), and each sync without a sweep makes `ds4.c` and
`ds4_metal.m` longer for nothing.

The child also carries one known dead path of its own:
`stream_needs_second_reasoning_guard()` ends in
`model_syntax != SERVER_MODEL_SYNTAX_QWEN`, and `server_model_syntax` has one
value here, so the guard and its two consumers in the OpenAI and Anthropic
stream writers never run (`AGENTS.md`, "Misleading-name traps").

## What Changes

- **Measure first.** On the synced tree:
  - `make 2>&1 | grep unused-function` and an `nm`-based list of functions with
    no referrer;
  - a coverage run (the method `AGENTS.md` records for `glm_graph_*`): one
    model session that exercises plain, MTP, vision, steering, disk KV and SSD
    streaming, with `-fprofile-instr-generate`, to list functions that are
    reachable by name but never executed;
  - for each candidate, the reachability proof SPEC.md §F asks for
    (constant-false predicate, no referrer, or a runtime probe), checked
    against this child's "Names that lie" table.
- **Remove** whole dead functions and whole dead blocks that the sync added
  for removed models or backends, with an `sf-ablate` marker at each non-obvious
  cut. Scattered dead conditionals stay unless the token saving is real
  (rule 16).
- **Remove the init-only pipelines** (owner decision after the sweep; older
  than the sync, kept as its own reviewable part): the GLM pipelines and seven
  generic ones that `ds4_gpu_init` builds and nothing dispatches, with their
  globals, null checks and releases, and the `kernel_glm*` kernels in
  `metal/dsv4_misc.metal` and `metal/moe.metal` with the helpers only they
  use. The rest of the older dead code is `101-legacy-ablation`.
- **Remove the second-reasoning-pass guard** in `ds4_server.c`: the predicate,
  the `guard_second_reasoning` fields and their two consumer blocks, with one
  marker. The inherited tests were already removed at the `0aaea5a` sync.
- **Record** in `AGENTS.md` any new "Names that lie" finding the sweep
  establishes.

Non-goals: no behaviour change; no removal of TP, RDMA, pipeline or the CPU
reference path (SPEC.md §B, StarForge rules 4-5); no renames of `ds4_*` files.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: code removal with identical behaviour)

## Impact

- `ds4.c`, `ds4_metal.m`, `ds4_server.c`, `metal/*.metal`, `Makefile`,
  `AGENTS.md`.
- Gates: `make -j8` with no warnings, `make test -j8`, `./ds4_test --server`,
  the StarForge parity oracle (token-identical, speed within 2%), and an A/B
  run with `--bitwise` against the synced `main`.
- Depends on `90`. Each later sync gains conflict sites at the cuts;
  rerere replays them when the conflict text is identical.
