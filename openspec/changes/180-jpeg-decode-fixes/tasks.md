# Tasks

GPU: one vision gate on Q4 (5.1). Everything else is CPU-only and model-less.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c180/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
`test_image_decode` line in its output, not only the exit code.

## 1. Branch and references (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c fix/180-jpeg-decode-fixes`. `git fetch upstream pull/1112/head pull/1110/head`; check the heads are still `a6ccd45` and `96ab887`, or record the new commits.
- [ ] 1.2 Build the D2 fingerprint harness and the D3 ASan test binary on `main`; save `$SCR/c180/fp-main.txt` and the ASan report for the two `*_luma_subsampled.jpg` fixtures (expect heap-buffer-overflow).

## 2. Step S1: #1112 (design D1, no GPU)

- [ ] 2.1 `git cherry-pick a6ccd45`. Run the step checks.
- [ ] 2.2 Step review: the two conversion loops and `jpeg_sample_chroma`'s clamping for component 0.

## 3. Step S2: #1110 (design D1, no GPU)

- [ ] 3.1 `git cherry-pick 96ab887`; resolve the README/`generate.sh` text conflict by keeping both PRs' rows. Run the step checks.
- [ ] 3.2 Step review: the single-component DC branch against the existing AC branch, and the sampling reset for one-component frames.

## 4. Model-less gates (no GPU)

- [ ] 4.1 `tests/test_image_decode` passes and names all eight fixture checks (four old, four new).
- [ ] 4.2 D3: the ASan build runs clean on every fixture.
- [ ] 4.3 D2: `$SCR/c180/fp-branch.txt` equals `fp-main.txt` on every ordinary JPEG; record the corpus size and the layouts it covered.

## 5. Vision gate (GPU: one run on Q4)

- [ ] 5.1 `tests/model_gates.sh <Q4> --mmproj gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf --image tests/vision-fixtures/jpeg/base_luma_subsampled.jpg --image tests/vision-fixtures/jpeg/base_gray_2x2.jpg`: every gate `PASS`, read from its lines.

## 6. Review and closing

- [ ] 6.1 Final pass over the touched region (no dead code, fixture README accurate).
- [ ] 6.2 `docs/upstream-prs.md`: `a6ccd45` and `96ab887` to `adopt -> 180-jpeg-decode-fixes`, with the gate results.
- [ ] 6.3 `openspec validate 180-jpeg-decode-fixes --strict` passes.
- [ ] 6.4 Report to the user in Italian. Land as one signed commit, with the PR author as `Co-authored-by`; delete `$SCR/c180/`; archive the change.
