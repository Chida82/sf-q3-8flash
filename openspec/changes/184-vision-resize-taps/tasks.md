# Tasks

GPU: closing guards only (5.2: model gates with vision, parity, one bitwise A/B on Q4). The decision (bitwise canvas and preprocessing speed) is CPU-only.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c184/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
`test_image_decode` line in its output.

## 1. Branch and references (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/184-vision-resize-taps`. `git fetch upstream pull/1008/head`; check the head is still `7d14832`; save the diff to `$SCR/c184/`.
- [ ] 1.2 `git worktree add --detach ../sf-q3-8flash-prev main` and build it.

## 2. Step S1: the port (design D2; no GPU)

- [ ] 2.1 Tap tables built once in `ds4_resize_rgb_bicubic`, read by the row workers, freed after the join; allocation failure reported by the Qwen call site. Add the flat-image check to `tests/test_image_decode.c`.
- [ ] 2.2 Run the step checks; step review.

## 3. Bitwise gate (design D1; no GPU)

- [ ] 3.1 Build `$SCR/c184/resize_diff.c` with the Makefile's `CFLAGS` and run it over the corpus at 1, 2 and 8 workers. Record the geometry count and the result.
- [ ] 3.2 Any differing float: drop the change (restore `main`'s files, record the geometry and count, mark `7d14832` `drop` in the registry with them), then go to 6.

## 4. Speed (design D3; no GPU)

- [ ] 4.1 ABBA timing of `ds4_image_preprocess_qwen4`, `../sf-q3-8flash-prev` against `.`, three sizes, 20 pairs each; pooled bootstrap 95% CI. Record in `$SCR/c184/steps.txt`.
- [ ] 4.2 Keep by the D3 rule; a neutral result drops the change as in 3.2.

## 5. Review and guards (GPU: Q4, sequential)

- [ ] 5.1 Final pass over the touched region; measure refinements like a step (and re-run 3.1 after any).
- [ ] 5.2 `tests/model_gates.sh <Q4> --mmproj gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf --image tests/vision-fixtures/qwen38/orbit.png --image tests/vision-fixtures/qwen38/maple.png`: every gate `PASS`. `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. `ab_bench.py --bitwise` against the current segment's start; append its row with step `perf/184-vision-resize-taps`. Put 4.1's figures in the commit message.

## 6. Closing

- [ ] 6.1 `docs/upstream-prs.md`: `7d14832` to `adopt -> 184-vision-resize-taps` with the figures, or `drop` with the reason.
- [ ] 6.2 `openspec validate 184-vision-resize-taps --strict` passes.
- [ ] 6.3 Report to the user in Italian. If kept, land as one signed commit, with the PR author as `Co-authored-by`. Delete `$SCR/c184/` and `../sf-q3-8flash-prev` if this change created it; archive the change.
