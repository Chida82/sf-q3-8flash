# Proposal

## Why

`docs/upstream-prs.md` was last reviewed on 2026-09-24. Since then 257
antirez/ds4 PRs were created or updated, #1056 was merged upstream (all 42
commits, including the ones this child dropped), #1238 brought a Qwen decode
series into `upstream/main`, and #1154/#1198 landed by hand. Proposals and
designs read the registry first (`openspec/config.yaml`), so its verdicts must
match what `upstream/main` (`b3f5018`) now holds and what reaches the Qwen
graph in this child.

The review behind this change (2026-11-13) covered every PR updated on or
after 2026-09-24 and checked each commit against `upstream/main` by ancestry,
by `git patch-id --stable` and by subject. Nothing was built or run.

## What Changes

- `docs/upstream-prs.md` (applied in this change):
  - "Last review: 2026-11-14", with a note that verdicts are relative to the
    child's `main` (synced to `fc80bd6`) and that a commit in `upstream/main`
    arrives with the sync to b3f5018 (`90`);
  - updated rows for #1062, #1056 (now merged), #1115, #1118 and #959;
  - 82 new PR rows, each with the change that plans it where one exists
    (`92`, `120`, `130`, `140`, `150`, `160`, `170`);
  - the #1056 commit table marked "in `upstream/main`" row by row, plus its 9
    new commits;
  - 30 new commit tables for reachable PRs, in the file's verdict
    vocabulary;
  - the Excluded list merged with the PRs the review found unreachable (174
    in all after deduplication), with notes on the ones a name could make look reachable.
- Three verdicts differ from the review draft, after checking the source on
  2026-11-14:
  - **#1118 stays `open`.** `7da9535` makes the idle prefill quantum the
    engine's prefill cap, but `cad7933` (also in `upstream/main`) limits that
    to DeepSeek V4.1. Qwen keeps the 2048-token quantum after the sync.
  - **#1125 `6c41f9b` is `not reachable from Qwen`.**
    `ds4_gpu_qwen4_moe_stream_tensor` calls only `prepare_selected_batch`.
    `prune_global`'s callers are the DeepSeek graph's seed paths and
    `ds4_gpu_routed_moe_one_tensor`, on the child's `main` and on `b3f5018`.
  - **#1125 `a0fe413` is reachable only in part.** The slot lost on a failed
    lock in `alloc_slab_slot` (through `prepare_load_buffers`) is reachable.
    Its `load_selected_missing`, `get_protected` and pending-load parts are
    not. The child's `prepare_selected_batch` already returns uninstalled
    reservations on its `gate_up_ready` error path.

- After `90` landed (2026-11-14), before this change: the verdict base moves
  to `b3f5018`; "arrives with the sync" becomes "came in with the sync"; the
  #1056, #1062 and #1238 rows and the #1238 commit table record what `90` took
  (D2 priming kept, D4 upstream's M5 path, the A/B figures, follow-ups `95` and
  `97`); the dropped #1056 commits record that they came in as upstream code
  that M5 resident does not select.

Non-goals: no code change. Commits that arrive with the sync keep their
verdicts until `90` records what it kept.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: documentation only)

## Impact

- `docs/upstream-prs.md` only.
- Later changes cite these rows. `120` drops `6c41f9b` and narrows
  `a0fe413`. `90` updates the #1056 and #1238 rows to what it keeps.
- Open from the review, carried as unchecked in the rows:
  - #1179's large commits were triaged by stats and kernel names only;
  - #1073's edits to shared `dsv4_*`/`dense.metal` kernels were not compared
    kernel by kernel;
  - server PR reachability came from hunk function names and PR bodies, not
    from traced calls;
  - whether the child's prefill head chunking changes Q2/Q4 logits (#1179
    `5c41319`).
