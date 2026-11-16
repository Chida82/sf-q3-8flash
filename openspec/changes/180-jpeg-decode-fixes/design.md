# Design

## Context

`third_party/iris/jpeg.h` is upstream's vendored decoder with `DS4:` patches.
The child has not changed it since the sync, so both PRs should apply with
`git cherry-pick` (the child's hunks sit 6 lines from the PRs': `1492`/`1547`
against `1486`/`1541`). `2768d0e` (#1113's subject, landed upstream in another
form) already validates `Ss`/`Se`/`Ah`/`Al` in the SOS segment. #1110's change
to the progressive scan dispatch runs after that validation, so it does not
change it.

## Decisions

### D1. Cherry-pick, one commit per PR, in order #1112 then #1110

Each PR adds lines to the same README table and `generate.sh`. Picking #1112
first and resolving #1110's text conflict by keeping both rows is the whole
merge. The `.jpg` fixtures are binary and come from the PR heads
(`git fetch upstream pull/1112/head pull/1110/head`). They are not
regenerated: `cjpeg` is not installed, and the PRs state the djpeg-exact
fingerprints the tests assert.

### D2. Proof that ordinary JPEGs are unchanged

The fixes take new branches only when `comp[0]` sampling is below the maximum
(#1112), when a DC scan carries one component, or when the frame has one
component (#1110). To check that nothing else moved:

- a scratch harness (`$SCR/c180/fp.c`, linked against `ds4_image.o`) prints
  the `ds4_image` fingerprint of every JPEG in a corpus: the four existing
  fixtures, and a set converted with `sips` (already on macOS) from the
  repository's PNGs (`tests/vision-fixtures/qwen38/*.png`) at several sizes
  and qualities, plus any further layout `sips` can write (grayscale,
  progressive);
- run it on `main` and on the branch: every fingerprint identical except the
  four new fixtures.

`sips` writes baseline 4:2:0 by default. Progressive output depends on the
macOS version; the harness records which layouts it actually got.

### D3. Memory check

Build `tests/test_image_decode` with `-fsanitize=address -g` (Apple clang
ships ASan, nothing to install). On `main` with the two
`*_luma_subsampled.jpg` fixtures it must report the heap-buffer-overflow. On
the branch it must run clean.

### D4. Vision gate

One model run checks that an image that used to fail now reaches the Qwen3-VL
encoder end to end: `tests/model_gates.sh` on Q4 with the mmproj and the two
new 40x24 fixtures `base_luma_subsampled.jpg` and `base_gray_2x2.jpg` as the
two `--image` arguments. Its vision gate compares MTP against plain on the
same images. The ordinary images are covered by D2, since equal pixels give
equal model input.

## Risks / Trade-offs

- **Vendored-code divergence:** none added; both hunks are upstream's text, so
  the next sync that takes the PRs (if upstream merges them) resolves by
  identity.
- **Grayscale 2x2 frames now decode** where they used to be rejected. That is
  the intended change; the fixture pins the result to `djpeg`.
