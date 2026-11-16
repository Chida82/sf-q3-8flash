# Tasks

GPU: one vision gate on Q4 (5.1). Everything else is CPU-only and model-less.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c180/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
`test_image_decode` line in its output, not only the exit code.

## Status

Done. Was: 5.1 (GPU vision gate on Q4); 6.2 replace "vision gate (GPU) pending" in the two `docs/upstream-prs.md` registry rows with the 5.1 result (the verdicts are already written); 6.3 re-run validate; 6.4 land, delete `$SCR/c180/`, archive. `$SCR/c180/` keeps `fp-*.txt`, the ASan reports and the harness sources.

## 1. Branch and references (no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c fix/180-jpeg-decode-fixes`. `git fetch upstream pull/1112/head pull/1110/head`; check the heads are still `a6ccd45` and `96ab887`, or record the new commits. Heads unchanged: `a6ccd45`, `96ab887`. Both applied with `cherry-pick --no-commit`, so the change lands as one commit.
- [x] 1.2 Build the D2 fingerprint harness and the D3 ASan test binary on `main`; save `$SCR/c180/fp-main.txt` and the ASan report for the two `*_luma_subsampled.jpg` fixtures (expect heap-buffer-overflow). `fp-main.txt`: 265 lines (258 ImageIO-written corpus JPEGs, 3 existing fixtures, the 4 new ones). ASan on `main`: heap-buffer-overflow READ at `jpeg.h:1492` (baseline) and `:1547` (progressive).

## 2. Step S1: #1112 (design D1, no GPU)

- [x] 2.1 `git cherry-pick a6ccd45`. Run the step checks. Conflict in `tests/test_image_decode.c` only (both blocks kept). The first `make test` failed on `base_luma_subsampled.jpg` because `ds4_image.o` was stale: the child's `Makefile` rule listed only `ds4_image.h`, not the vendored `third_party/iris/jpeg.h`/`png.h` it includes (upstream lists them). Added both; then green.
- [x] 2.2 Step review: the two conversion loops and `jpeg_sample_chroma`'s clamping for component 0. `sx`/`sy` stay below the real luma extent (always inside the MCU-padded plane), the neighbours clamp to it, and the unusual-ratio fallback reads the same in-bounds sample. `y_full` keeps the direct read for full-resolution luma. No finding.

## 3. Step S2: #1110 (design D1, no GPU)

- [x] 3.1 `git cherry-pick 96ab887`; resolve the README/`generate.sh` text conflict by keeping both PRs' rows. Run the step checks. Conflicts in the test, README and `generate.sh`; the merge dropped one shared `return 1;` after the `prog_luma_subsampled` check, restored. README prose merged into one paragraph; `generate.sh` prints all six files once.
- [x] 3.2 Step review: the single-component DC branch against the existing AC branch, and the sampling reset for one-component frames. The one-component DC branch reuses the AC branch's raster walk, storage mapping and restart handling (which already resets `dc_pred`); the reset to 1x1 runs after the 1..4 range checks and before `max_*_samp`. No finding.

## 4. Model-less gates (no GPU)

- [x] 4.1 `tests/test_image_decode` passes and names all eight fixture checks (four old, four new). `test_image_decode` was silent on success; it now prints one `test_image_decode: <fixture> ...: OK` line per check, and `make test` shows all eight.
- [x] 4.2 D3: the ASan build runs clean on every fixture. ASan build of `tests/test_image_decode` (8 OK lines) and of the harness over the corpus plus the new fixtures: no report.
- [x] 4.3 D2: `$SCR/c180/fp-branch.txt` equals `fp-main.txt` on every ordinary JPEG; record the corpus size and the layouts it covered. 261 of 265 lines identical; only the four new fixtures differ, each to the fingerprint the test asserts. Corpus: 258 JPEGs from `maple.png`/`orbit.png` at 8 sizes (1x1 to 1023x767), 4 qualities, written by ImageIO: baseline and progressive, each gray 1x1, YCbCr 4:4:4 and 4:2:0 (plus two `sips` defaults).

## 5. Vision gate (GPU: one run on Q4)

- [x] 5.1 `tests/model_gates.sh <Q4> --mmproj gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf --image tests/vision-fixtures/jpeg/base_luma_subsampled.jpg --image tests/vision-fixtures/jpeg/base_gray_2x2.jpg`: every gate `PASS`, read from its lines. 2026-11-16: first run FAIL on mtp-identity speed only (prompt 10, one-word answer, `mtp 3` at 19.1 t/s vs plain 55.5; 0 of 36 runs differ); re-run all PASS (mtp-identity 130 s, mtp-limits, mtp-turns, ds4_test, vision, host-paths). The change touches only the JPEG decoder, so the one-word speed flag is noise.

## 6. Review and closing

- [x] 6.1 Final pass over the touched region (no dead code, fixture README accurate). Fixture README now also lists `prog_sos_se_oob.jpg`. `Makefile` dependency fix and the test's OK lines are the only lines beyond the PRs.
- [x] 6.2 `docs/upstream-prs.md`: `a6ccd45` and `96ab887` to `adopt -> 180-jpeg-decode-fixes`, with the gate results.
- [x] 6.3 `openspec validate 180-jpeg-decode-fixes --strict` passes.
- [x] 6.4 Report to the user in Italian. Land as one signed commit, with the PR author as `Co-authored-by`; delete `$SCR/c180/`; archive the change.
