# Design

## Context

See proposal.md for the motivation and the step list; the specs are in
`specs/mtp-speculation/spec.md`.

State of the child that shapes the port:

- `main` has upstream up to the merge-base `0aaea5a`. That base already
  contains the modified landings of three #1062 commits the five steps touch:
  - `548cdaf` bounds speculative batches and rewrote the batched entry's
    submit block;
  - `e2cba0b` is the batched predictor (`qwen4_batch_mtp_drafts`), which
    gathers embeddings on the host and stages row by row;
  - `3077786` is the batched draft decision, which brought its own
    `qwen4_ema`.

  The PR's commits were written before those landings.
- The child renamed `glm_graph_begin_commands_if_needed` to
  `qwen4_graph_begin_commands_if_needed` at bootstrap; upstream still uses the
  old name.
- A trial port of steps 1-5 on a scratch clone gives the complete list of
  conflicts and semantic breaks (D2):
  - `acce8da` has one conflict;
  - `be4cec8` and `926ee12` apply cleanly;
  - `0a89a04` and `1cd83e3` have two name-only conflicts each;
  - the build then fails in two places: the batched predictor and a duplicate
    `qwen4_ema`.

  With those fixed, the tree builds without warnings and
  `make test-qwen4-kernels` passes. Nothing model-backed ran on it.
- Tools this change uses and does not modify:
  - `speed-bench/ab_bench.py`, whose A/A noise floor on the M5 Max plateau is:
    - MTP decode ±1-2% per pair;
    - tokens per cycle exactly equal;
    - prefill 2048 of the MTP kinds up to ±7%, since it is the first prefill
      of each process;
  - `tests/test_qwen4_mtp_limits.py`;
  - `ds4_test` with `DS4_TEST_GLM_MTP=1`;
  - `speed-bench/session_concurrency_bench --spec --verify`;
  - `tests/test_qwen4_checkpoint_replay.py`;
  - StarForge `tools/parity-check.sh`, whose prompt set has one `--mtp` prompt.

## Goals / Non-Goals

**Goals:**
- Land each step as its own reviewable unit, with its A/B verdict against the
  previous step recorded.
- Prove the spec's invariants with existing tools. New test code is added only
  where no existing tool reaches.
- Leave the MTP region better than the PR wrote it: reviewed against the
  child's rules and idiom, with the refinements measured (D11).

**Non-Goals:**
- No change to the harness, the bench or the parity oracle.
- No batched-server depth-3 cycles (`822de06`) and no draft-head prefix
  (`4d8b5dd`).
- No M1-Max-specific kernels from #1056 (the Q8 EH projection of `b86c8ae`).
- No Q2 measurement. `70-q2-kernels-m5` owns the Q2 pack. The gates here run
  on the default Q4 model.

## Decisions

### D1. Port by cherry-pick, provenance in the commit message

Each step is `git cherry-pick -n <sha>` on the branch `perf/30-mtp-cycle`, cut
from `main`. Conflicts are resolved at the sites D2 lists and nowhere else.
When the user asks for commits, each kept step becomes one commit:

- the upstream subject and body;
- a `(cherry picked from commit <sha>)` line;
- one paragraph naming the hand-ported sites and the step's measured verdict;
- the attribution line.

The upstream author is kept. The child's own commits frame the steps:

- the Segment 1 start row, first;
- the review refinements (D11), after the last step, if the final pass takes
  any;
- the registry, docs, final record row and this change's artifacts, last.

Alternative: rewrite the steps as the child's own commits. Rejected: that
loses the link to the upstream patch, and the next sync review needs it to
tell "already taken" from "new".

### D2. Hand-ported sites

Taken from the trial port. Nothing else conflicts or breaks.

| Step | Site | Resolution |
|---|---|---|
| 1 `acce8da` | batched speculative entry, submit block (rewritten by `548cdaf`) | take the PR's tail-flush loop before the batched forward; keep `548cdaf`'s `if (!ds4_gpu_end_commands()) ok = false;` |
| 1 | `qwen4_batch_mtp_drafts` row-by-row stage and combine calls | pass the new row count `1u` (the calls still stage one row each until step 4) |
| 3 `926ee12` | second `qwen4_ema`, added next to `qwen4_spec_depth` | keep one definition, the earlier one in the file, which both the session policy and the batched decision (`3077786`) call; delete the other |
| 4 `0a89a04` | `qwen4_graph_mtp_steps`, `qwen4_graph_mtp_chain_step` | name-only: write `qwen4_graph_begin_commands_if_needed` |
| 4 | `qwen4_batch_mtp_drafts` | replace the host gather (`qwen4_ref_row` into `batch_head_x`) and the per-row stage/combine with a write of the N ids to `mtp_next` and one `qwen4_mtp_stage` and one combine over N rows, as the PR head `1ab00b5` does. `mtp_next` is shared scratch, so the batch arena inherits it through `qwen4_graph_transfer_scratch` |
| 5 `1cd83e3` | `qwen4_graph_mtp_steps`, `qwen4_graph_mtp_chain_step` removal | name-only, as step 4 |
| 5 | `qwen4_batch_mtp_drafts` argmax | pass `NULL` for the new row-list argument (full vocabulary head); the PR head's `head_rows` prefix belongs to the dropped `4d8b5dd` |

A later step's conflict with an earlier step's hand port is resolved in the
same way. The build must pass after every step, not only after step 5.

### D3. Step snapshots without commits

AGENTS.md rule 14 forbids committing without a request. The harness still
needs the previous step as a tree, so each step is kept as a git tree object,
not as a commit. Staging is allowed.

Snapshots leave out `openspec/`, whose `tasks.md` changes while the work goes
on. `X` below stands for the pathspec `-- . ':!openspec'`.

- **Snapshot.** After the start row and after each step that passes its
  gates, run `git add -A X` and record `T_k=$(git write-tree)` in the scratch
  dir, with the step's message draft.
- **A tree.** A for step k+1 is a detached worktree `../sf-q3-8flash-prev` of
  `main`, brought to `T_k` with `git restore --source=T_k --staged --worktree
  -- .`. The build artifacts there are untracked and survive, and `make`
  rebuilds what the restore touched.
- **Dropped step.** `git restore --source=T_{k-1} --staged --worktree X`
  restores the working tree.
- **Replay at the user's commit request.** For each snapshot in order (`T_0`,
  the kept `T_k`, `T_refine`, `T_final`), run `git restore --source=T_k
  --staged --worktree X` and `git commit`. The last
  commit adds `openspec/` as well. The commits are signed, as `commit.gpgsign`
  requires; `git commit-tree` would not sign.

`git cherry-pick -n` accepts an index that differs from `HEAD`, so step k+1
applies on top of step k's staged state. A trial on the scratch clone
confirmed the whole cycle:

1. snapshot;
2. cherry-pick onto it;
3. snapshot again;
4. restore the first snapshot;
5. commit the second, while `openspec/` edits and untracked files stay as
   they are.

Alternative: rsync copies of the tree per step. Rejected: they are larger, and
the commit replay would need diffs rebuilt from them.

### D4. What each step is measured on

A is the previous kept step (for step 1, `main`). B is the working tree.

| Step | `ab_bench.py` arguments | Target metric | Extra gate |
|---|---|---|---|
| 1 priming | `--kinds mtp-code,mtp-prose` | MTP decode and tokens per cycle, both kinds | bitwise probe (D6) |
| 2 three-row geometry | `--kinds mtp-code --env DS4_QWEN4_MTP_DEPTH=3` | MTP decode at depth 3 | — |
| 3 depth policy | `--kinds mtp-code,mtp-prose` | MTP decode, both kinds | — |
| 4 GPU gather | `--kinds mtp-code,mtp-prose --bitwise` | MTP decode | tokens per cycle and k1/k2/k3 counts exactly equal |
| 5 chained draft | `--kinds mtp-code --env DS4_QWEN4_MTP_DEPTH=3 --bitwise` | MTP decode at depth 3 | as step 4 |
| 6 cache-only priming | `--kinds mtp-code --budget 600 --bitwise` | prefill 2048 with `--mtp` | as step 4 |

Depth is pinned where a step only changes depth-3 cycles (steps 2 and 5).
Under the old automatic policy those cycles are rare, and a pinned depth
measures the step itself, not the policy. Plain kinds are not run per step:
without `--mtp` the engine allocates no predictor buffers, so none of the new
code is reachable, and D7 checks this once at the end.

Steps 4-6 claim identical drafts. There the `--bitwise` gate is meaningful on
the MTP kinds: identical drafts give identical cycle sequences, so the decode
dumps must match to the bit. In steps 1-3 the drafts change. A different
acceptance pattern changes which verify-row groupings produce the final
logits, so the decode dumps can differ while the tokens are equal. Those
steps are gated on tokens.

### D5. Keep or drop

A step is kept when, in its D4 run, both hold:

- the target metric's median ratio is above 1 by more than that metric's A/A
  noise floor;
- no other throughput metric of the run (decode, prefill) is below 1 by more
  than its noise floor.

Tokens per cycle is exact for a given prompt, so its noise floor is zero, and
any change is a property of that one 128-token sample, not a measurement
error. It is reported and explains the decode figure. The guard, though, is
the kind's decode throughput. (Found at step 1: prose tokens per cycle
1.51 -> 1.49 with prose decode -1.5%, inside its noise, while code gained
8.3%.)

Exceptions:

- Step 1 may lower prefill 2048 with `--mtp` by up to 5%. The PR measured 3.4%,
  and the decode gain pays for it. A larger loss drops the step.
- Step 4 is kept when it is neutral (within noise): it removes the 80 MiB
  priming arena and a host round trip, and step 5 is written on top of it.
- Step 5 is also kept when it is neutral and bit-identical. It deletes the
  separate chain function and folds the cycle's four drafting sites into one
  helper, so it pays in reading cost (D11). It also saves one submission and
  one readback per depth-3 cycle. (Measured: +0.6%, the PR's own figure.)
- Prefill's per-pair noise (up to ±7%) is larger than the gains a step can
  make on it. A prefill gain is therefore established when the 95% bootstrap
  interval of the pair-ratio median, computed from the run's `samples.csv`,
  excludes 1. (Step 6: +2.1% median over 36 pairs, interval [+0.3%, +2.9%].)
- A result with fewer than two pairs (exit 3) is repeated once with
  `--budget 600`. If it is still inconclusive, the step is dropped, except
  step 4, which follows the neutral rule.

A dropped step is recorded in the registry as `drop` with the measured
figures. Later steps are then ported on the previous kept step. A step that
does not apply without the dropped one stops the change (Risks).

### D6. Correctness per step and at the end

Every step:

- `make -j8` with no warnings;
- `make test -j8`, reading the test names in the output (AGENTS.md rule 19);
- `make test-qwen4-kernels`;
- `python3 tests/test_qwen4_mtp_limits.py --model <Q4>`: MTP equals plain
  greedy at prefill chunks 1, 2 and 128 (unfused), at depth 3;
- the harness token gate of D4.

Step 1 also gets a **bitwise probe**. `ab_bench.py --kinds mtp-code --bitwise
--preheat 0 --budget 60` checks the dumps in the warm-up and then stops for
lack of budget. The step passes if the probe exits 3 (every dump identical),
or exits 1 naming `frontier_002048.decode.logits.json`: the prefill dump
matched and only the decode differs, as D4 expects. A failure naming the
prefill file means priming touched the target's logits, and the step fails.

At the end, on the final tree:

- `DS4_TEST_MODEL=<Q4> DS4_TEST_GLM_MTP=1 ./ds4_test`: rewind, snapshot,
  restore-reuse and prefill checkpoints with MTP;
- `tests/test_qwen4_ngram_state`: batched speculation with snapshot loads;
- `speed-bench/session_concurrency_bench --spec --verify --concurrency 2`:
  batched MTP against plain greedy;
- `python3 tests/test_qwen4_checkpoint_replay.py --model <Q4>`: disk-KV
  restore under `--mtp` across a server restart;
- `tests/test_qwen4_cli_vision.py` with the local `mmproj` and two PNGs made
  with `sips` in the scratch dir: both modes complete, and its `ordinary.stdout`
  and `mtp.stdout` are identical, because priming is skipped for images;
- the cross-build checkpoint check (D8);
- `tools/parity-check.sh sf-q3-8flash <Q4>` from the StarForge checkout.

### D7. Performance record

- **Start row, first task.** `git worktree add --detach ../sf-q3-8flash-start
  91f225a`, then an A/A run with `--a` and `--b` both on it, all kinds. The row
  goes at the head of Segment 1, and the "Start commit" line names `91f225a`.
  `9570ca9`, the head of `main`, only adds OpenSpec files, so the code is the
  same.
- **Final row.** `--a ../sf-q3-8flash-start --b .`, all kinds. It is run
  without `--bitwise`, because the MTP decode dumps legitimately differ from
  the start (D4). The printed row is appended, and its `step` cell is the
  branch.
- **Plain bit-identity.** One more invocation, `--a ../sf-q3-8flash-start --b .
  --kinds plain --bitwise`. It proves the spec's "Plain mode is unaffected" and
  checks that plain speed has not moved.

### D8. Cross-build checkpoint check

The spec requires compatibility in both directions, and no existing test spans
two builds. The check follows `test_qwen4_checkpoint_replay.py`'s shape:

1. Each build's server answers two turns of a ~3k-token conversation under
   `--mtp` with a disk-KV directory, then shuts down. The directory then holds
   the continued checkpoints.
2. Each build then answers the third turn from each directory.
3. A cross read must reuse the checkpoint and give byte-for-byte the answer of
   the same build reading its own directory.

The reference is a same-build read, not an empty cache. Resuming from a
checkpoint keeps the earlier turns' stored reasoning in the context, while a
history rebuilt from nothing drops it, so the two prompts differ (3176 against
3138 tokens here). The procedure is a scratch script, recorded in tasks.md. It
becomes a repository test only if a later change needs it again.

### D9. Cache-only priming (step 6)

Attempt it only if step 1's run shows the MTP-mode prefill cost above the
noise, meaning the median ratio of prefill 2048 is below 0.97. Otherwise there
is nothing measurable to recover, and the step is recorded as not attempted.

For prompt rows the priming needs only what the nextn layer writes to its
caches: the attention input mix and then the K, V and indexer-K projections
with their norm, RoPE and cache writes. The Q projection, the attention
itself, the output projection, the FFN mix and the MoE only feed the row's
residual, which nothing reads for history rows. The tail row keeps the full
pass at flush time. The implementation calls the kernels the full path
already uses for those writes, with the same arguments, so the cache bytes
match by construction. No new kernel is added.

The gate is identical drafts (D4 step 6). The `b86c8ae` M1 Max Q8 EH kernel
and its device gating are not taken.

### D10. Registry and docs

`docs/upstream-prs.md`:

- adopted commits keep `adopt -> 30-mtp-cycle`, and the reason becomes the
  measured verdict. The child commit is found by its `cherry picked from`
  line, because a commit cannot name its own SHA;
- dropped ones become `drop` with the measured reason;
- `b86c8ae` becomes `idea -> 30-mtp-cycle` taken or not attempted, with the
  figure;
- `a6ad636` becomes `drop` (needs SSD streaming; the draft-identity gate
  covers the risk);
- the #1062 PR summary cell is updated.

`docs/SPECULATIVE_DECODING.md` replaces "adaptively uses depth two or three"
with the priming and the measured depth rule, and keeps the
`DS4_QWEN4_MTP_DEPTH` pin.

### D11. Review of the ported code

A PR's code is where the work starts, not where it ends. The code is
reviewed twice, and whatever the review improves is measured like a step.

**Step review**, after each step builds and passes its checks and before its
A/B. It reads the step's diff against the previous snapshot and every
function the diff touches, in full. Findings go to the scratch
`review.md` in two classes:

- *Fix now*: anything that would make the step wrong or its measurement
  misleading, or that breaks a child rule:
  - a correctness problem;
  - a path for a model or backend the child does not have;
  - an `#ifdef` where the child deletes;
  - an error path that leaks a tensor view or leaves state half-set;
  - an upstream name the child has already renamed.

  It is fixed inside the step, and the step's commit paragraph names it.
- *Refine later*: everything else. It waits for the final pass, so that the
  step's A/B and its registry verdict measure the upstream patch as ported.

**Final pass**, after the last step, over the whole MTP region as it now
stands (tasks 8.1 lists it). The criteria:

- AGENT.md's quality rules:
  - the smallest direct implementation;
  - no speculative variants;
  - comments only for non-obvious model mechanics, cache lifetime, memory
    policy and synchronisation;
  - public APIs kept narrow.
- The surrounding code's idiom: the `qwen4_` naming, the `ok &&` chains with
  views freed on every path, and the comment density of the neighbouring
  functions.
- Deletion of what the port made dead in this child, found by reading the
  callers, not the names (AGENTS.md "Names that lie"):
  - helpers and session fields;
  - environment toggles whose alternative no longer works. For example,
    whether `DS4_QWEN4_MTP_GPU_ARGMAX` still selects a working path once the
    chained draft reads its id from the GPU argmax buffer;
  - logic duplicated between the single-session and the batched predictor.
- Speed the PR left on the table, only where the output stays identical:
  host round trips, redundant copies or views, submissions that could be
  merged.
- Tests: each new branch or state transition has its one focused
  regression (AGENT.md). Otherwise the nearest existing test is extended.

An improvement that would change numerics or drafts is not a refinement. It
becomes a measured step of its own, or a note for a later change.

**Gate.** The refinements are measured together against the last kept step
with `--bitwise` on both MTP kinds:

- drafts must be identical, so tokens per cycle are equal and the dumps
  match;
- no headline metric may fall below 1 by more than its noise floor.

A purely readable refinement passes at neutral speed. A finding that fails
the gate is reverted and recorded as measured and left.

**Trade-off.** Every rewrite moves the child's text further from the PR's.
The PR is unmerged, and if it lands upstream in another shape, these regions
conflict anyway (Risks). So a refinement is taken when it pays in
correctness, speed or reading cost (AGENTS.md rule 16). A cosmetic reshuffle
of upstream lines is not taken.

Alternative: take the PR as ported, as long as it measures well. Rejected by
the owner: this child exists to be the cheapest tree to read and optimise
further. The rule applies to every change (see `openspec/config.yaml`).

## Risks / Trade-offs

- [Step 1 shows no gain on this child] → Steps 4 and 5 are written on top of
  the priming, so later steps lose their base. The change stops after step 1's
  verdict and reports, with the measurement, before porting anything else.
- [Prefill 2048 of the MTP kinds is the first prefill of a process, ±7% per
  pair] → Step 1's allowed cost (5%) and step 6's gain sit inside that range.
  Step 6 runs with `--budget 600`, and step 1's prefill verdict is read as a
  bound, not as a point estimate.
- [An automatic-depth result depends on the prompt] → Both kinds are measured
  in step 3. The spec only requires "not below the replaced policy beyond
  noise".
- [Sampled (non-exact) MTP text changes, because drafts change] → Expected, and
  greedy and exact sampling are unaffected. The proposal's Impact states it;
  no test pins sampled MTP text.
- [Batched server path] → The batch entry refuses sessions still in prefill
  (`prompt_rows`), and the tail is flushed before the batched forward (D2).
  `session_concurrency_bench --spec --verify` checks it end to end at C=2.
- [Payloads grow by the nextn KV over the prompt] → About 1/13 of the
  attention KV. The disk-KV space limit already bounds the cache. The format
  is unchanged (D8).
- [Measurement time] → About ten harness invocations: the start row, steps
  1-5, the step 1 probe, the refinement gate, the final row and the plain
  bitwise run, plus step 6 if attempted. At 10-15 minutes each, with the cool-down to Nominal that
  preflight requires, that is about two hours of machine time.
- [Found at 9.5, pre-existing: MTP greedy differs from plain greedy in a
  multi-turn conversation with images] → In `tests/test_qwen4_cli_vision.py`,
  the first image turn matches and the next turn diverges from its first
  line, the same way at `91f225a` and in the final tree. The final tree's MTP
  output is byte-identical to the start's, and its plain output as well. With
  `-n 600` the first answer ends on its own and the second still diverges, so
  an output-limit overshoot does not explain it; the cause is open. Out of
  scope here (text MTP is lossless, and this change leaves image MTP output
  unchanged), and reported for a change of its own. The spec's image
  scenario states what this change guarantees.
- [Future sync] → If upstream merges #1062, these regions conflict once, and
  rerere has nothing recorded for them. The registry lines name the child
  commits, so the resolution is "take upstream's version where the child took
  the same commit". Where the final pass (D11) rewrote a region, the
  refinement commit says what it changed and why, so the sync can re-apply
  it on top of upstream's version or drop it.
- [The review finds nothing worth taking, or finds too much] → "No
  refinement" is a valid outcome and is recorded. A finding that needs more
  than the bitwise-neutral gate allows goes to a later change rather than
  growing this one.

## Migration Plan

No format or flag changes. Deploying a later build over an earlier one keeps
disk-KV caches valid in both directions (D8). Rollback is a revert of the
step commits in reverse order. Each step builds and passes its gates on its
own, so a partial revert is valid as well.
