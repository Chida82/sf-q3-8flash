# Design

## Context

The facts are in proposal.md, "What is known". The PR is `4642526` on the
upstream ref `refs/pull/1056/head`. Fetch it as
`git fetch upstream refs/pull/1056/head:refs/remotes/upstream/pr-1056`. Its
commits are ported one by one onto the child. The child's M5 kernels are newer
than the PR's base, so no commit applies cleanly. Every port is a manual
merge that is then checked against the resident path.

## Goals / Non-Goals

**Goals:**
- Qwen runs with `--ssd-streaming` on both packs, token-identical to
  resident.
- The resident path stays bitwise identical and as fast as before.
- Streamed throughput on emulated 48 GB and 40 GB machines is measured and
  documented.
- Phase B steps are each kept or dropped on measured streamed speed.

**Non-Goals:** see proposal.md, "Not in scope".

## Decisions

### D1. Build on the generic stream expert cache, as the PR does

`e37f185` calls `ds4_gpu_stream_expert_cache_*` for entries, slot addresses,
batch preparation and accounting. A Qwen-only cache would duplicate about
800 lines the child already has and would diverge from upstream at every
sync. The generic code is marked `sf-keep` at its entry points first, so no
ablation removes it while this change is open. At the end, the reachable set
is known (`nm` for referrers and a coverage probe with `--ssd-streaming`). The
unreachable DeepSeek-only remainder becomes a later ablation change, not part
of this one.

### D2. Address tables reach every routed kernel the child has

The PR guards a per-expert address table behind function constant 906
(`qwen4_expert_addresses`). With the constant false or undefined, the
compiler removes the path, so resident pipelines are the same code. The
child's routed kernels that need the path, besides the PR's own:
- `kernel_qwen4_moe_down_mxfp4_pf` and its shared-slot helpers;
- `kernel_qwen4_moe_mid_iq2` (NR1/NR2);
- `kernel_qwen4_moe_down_q2k`;
- the tensor tiles, nax/nax64/nax16/nax8 and their float and compensated
  levels, with the tail launches.

Each is extended the way the PR extends its generic kernels:
- the weight pointer comes from the table when the constant is set;
- nothing else changes.

A kernel the port cannot extend falls back, when streaming, to the generic
kernel the PR addresses. It is chosen on the host by `ssd_streaming`, and
never while resident.

### D3. Proving identity

- **Resident:** `ab_bench.py --a ../sf-q3-8flash-prev --b . --bitwise` against
  `main`. Every step requires `PASS (tokens; bitwise)` and no metric wholly
  below zero. `make test-qwen4-kernels` hashes must equal `main`'s.
- **Streamed:** `ab_bench.py --a . --b . --b-bench-arg=--ssd-streaming` (the
  S0 option). The gate compares streamed tokens against resident tokens,
  per kind and frontier. It runs at 128 GiB, then with the emulation on B
  only, `--b-bench-arg=--simulate-used-memory --b-bench-arg=80GB` (about a
  48 GB machine) and `88GB` (about 40 GB, the smallest the host's 108.8 GiB
  wire limit allows). A resident side never carries
  the lock: the engine refuses it, after it hung the machine once. Logit bitwise is not required:
  streamed and resident may differ in the last bit only where the PR
  documents a fallback. Tokens must match.
- **Unit:** `test-qwen4-ssd-experts` and `test-qwen4-memory`, ported and
  extended with the child's kernels of D2, addressed against resident,
  byte-exact.

### D4. Phase B verdicts on streamed runs

Phase B changes scheduling and I/O overlap, which the section cuts hide
(config.yaml). So its steps are judged on the harness, not on section time:
- A is the previous step and B the candidate;
- both builds get `--bench-arg=--ssd-streaming` and the 48 GB emulation;
- a step is kept by the existing rule;
- its resident guard is one `--bitwise` run without bench arguments.

SSD timing varies more than GPU timing. The A/A noise floor is measured
once, streamed at 48 GB, before phase B.

### D5. S0 before everything

Bench arguments are a small tool change with unit tests and one A/A run.
With them, every later check is a harness call. Otherwise it would be a
hand-made script. Change 81 plans `--gen N`. With S0 landed, 81 can use
`--bench-arg=-n --bench-arg=512` instead. 81's own planning decides that.

### D6. The refusal and the docs

The check in `ds4_engine_open` drops `e->ssd_streaming` from the Qwen
condition, with the PR's message text. `AGENTS.md` changes in two places:
- its "Misleading-name traps" paragraph says engine open rejects SSD
  streaming for Qwen; it now says only TP, pipeline and power throttling;
- its product contract row stays, and gains the streaming mode.

`docs/SSD_STREAMING.md` loses any DeepSeek-only paragraph the child does not
support (rule 11) and gains the Qwen memory policy with the measured minimum
RAM.

### D7. Memory safety of the runs

Streaming runs load the model with a bounded cache. The emulation locks up
to 96 GiB. Only one model process runs at a time, with nothing beside it.
Before an emulated run, the harness preflight must see no other large
resident process, and the locked memory is released when the bench exits.

## Risks / Trade-offs

- **The M5 kernels diverged**, so the port conflicts in every routed kernel →
  D2's fallback keeps correctness, and each extended kernel has its own
  byte-exact test.
- **A function constant can change resident code generation** → D3's bitwise
  resident gate and the kernel hashes catch it. If they fail, the address path
  moves into separate kernel instances.
- **SSD noise hides small phase B effects** → the A/A floor is measured
  first, and inconclusive runs are repeated once and pooled.
- **Future syncs:** `qwen4.metal` and the bind path conflict until upstream
  merges #1056. rerere replays the resolution, and the `sf-keep` markers
  explain it.
- **Emulation is not a real small Mac:** locked memory approximates the
  pressure but not a slower SSD. The docs say where the figures come from.

## Open Questions

- None blocking. The emulation sizes (80 and 96 GiB) are approximations,
  and are recorded as such.
