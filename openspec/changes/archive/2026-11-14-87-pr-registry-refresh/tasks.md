# Tasks

Input: the 2026-11-13 review (`pr-review.md` and `commit-status.tsv` in the
session scratchpad). Read-only checks ran on the plan worktree (`main`,
`765e9a5`) and on `upstream/main` via `git show`.

## 1. Registry

- [x] 1.1 Set "Last review: 2026-11-14" and add the note on the verdict base (child `main` at `fc80bd6`, `upstream/main` at `b3f5018`, sync `90`). Verify: the next search date reads `updated:>=2026-11-13`, the day the PR list was taken.
- [x] 1.2 Update the rows for #1062, #1056, #1115, #1118 and #959. Verify: #1056 reads merged (`4ef9e4d`) with head `9eb4a12`, and #1115 names `92-qwen-template-fix-1115`.
- [x] 1.3 Add the new PR rows with their planned change. Verify: every PR number in the review's tables (a) appears exactly once in the PRs table.
- [x] 1.4 #1056 commit table: mark each row as in `upstream/main`, arriving with `90`, and add the 9 new commits. Verify: the merge rows carry no suffix, and the section header names `9eb4a12` and `4ef9e4d`.
- [x] 1.5 Add the commit tables for the reachable PRs, using only the file's verdict vocabulary. Verify: listing the third cell of every commit row gives only vocabulary verdicts (the older `split: ...` row of #1056 is kept as it was); qualifiers such as "low priority" sit in the reason.
- [x] 1.6 Merge the Excluded list. Verify: the merge script asserts that no PR is both excluded and in the PRs table.

- [x] 1.7 After `90` landed: move the verdict base to `b3f5018` and put the sync outcomes into the #1056, #1062 and #1238 rows and the #1238 table. Verify: `rg 'arrives? with|fc80bd6|decides whether' docs/upstream-prs.md` finds nothing.

## 2. Source checks behind the corrections

- [x] 2.1 #1118: `git show cad7933` limits the idle quantum to `ds4_engine_is_deepseek41`. Verdict stays `open`.
- [x] 2.2 #1125: list the callers of `prune_global`, `load_selected_missing`, `clear_layer` and `alloc_slab_slot` in `ds4_metal.m` on the worktree and in `git show upstream/main:ds4_metal.m`. Verify: `ds4_gpu_qwen4_moe_stream_tensor` reaches only `prepare_selected_batch`, which reaches `clear_layer` and, through `prepare_load_buffers`, `alloc_slab_slot`.
- [x] 2.3 Cite the child sites the new reasons name (`ds4.c:2086-2087`, `ds4.c:29722`, `ds4.c:29724`, `ds4.c:32412`, `ds4_metal.m:11270`, `metal/qwen4.metal:1370`/`1532`, `ds4_server.c:3426`), each read on the worktree.

## 3. Closing

- [x] 3.1 `openspec validate 87-pr-registry-refresh --strict` passes.
- [x] 3.2 The owner reads the three corrections in proposal.md.
- [x] 3.3 Land as one signed commit on `main` when the owner asks. It touches `docs/upstream-prs.md` only; `90` landed first without registry edits, so 1.7 carries its outcomes.
