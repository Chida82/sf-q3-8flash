# Proposal

## Why

The server decodes every client JPEG with the vendored Iris decoder
(`ds4_image_decode_memory` -> `jpeg_load_mem`, `ds4_image.c:264`) before the
Qwen3-VL encoder sees it. Two upstream PRs fix defects that are present in the
child's `third_party/iris/jpeg.h`:

- **#1112** (`a6ccd45`): when a frame gives luma lower sampling factors than
  Cb or Cr (for example `-sample 1x1,2x2,1x1`), the Y plane is smaller than
  the image. The colour conversion still reads it as a full-size plane
  (`jpeg.h:1492` baseline, `:1547` progressive), past the end of its heap
  buffer. AddressSanitizer reports a heap-buffer-overflow on the PR's
  fixtures. The input comes from the network, so this is a read past a heap
  buffer at a trust boundary.
- **#1110** (`96ab887`): a scan with one component is non-interleaved, and its
  blocks come in raster order (ITU T.81 A.2.2). The decoder groups them by MCU
  anyway. A progressive file with one DC scan per component decodes to wrong
  pixels (`jpeg.h:1032` treats every DC scan as interleaved), and a grayscale
  frame that declares 2x2 sampling is rejected.

Both are quality fixes under the intake criteria: the model gets the right
pixels, or the right error, instead of wrong pixels or memory past a buffer.
#1113 (reject a progressive band past coefficient 63) is already in `main` as
upstream `2768d0e` and is not part of this change.

## What Changes

- Port `a6ccd45`: when Y is subsampled, read it through
  `jpeg_sample_chroma` (the same triangle upsampling the chroma planes use).
  Full-resolution luma, the usual layout, keeps the direct read.
- Port `96ab887`: DC scans with one component take the non-interleaved path,
  and a single-component frame has its sampling factors reset to 1x1.
- Add the four fixture JPEGs and their four `check_jpeg` cases to
  `tests/test_image_decode.c`, which `make test` already runs. Update the
  fixture README and `generate.sh` as the PRs do. The binary fixtures come from
  the PR heads, so no `cjpeg` is needed.

Ordinary JPEGs (full-resolution luma, interleaved scans) must decode to the
same bytes as before. A fingerprint comparison over a corpus checks that
(design D2).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: image decoding of malformed or unusual JPEGs only; ordinary JPEGs decode byte-identically)

## Impact

- `third_party/iris/jpeg.h` (two hunks per PR; upstream text, no child
  markers needed), `tests/test_image_decode.c`, `tests/vision-fixtures/jpeg/`.
- `docs/upstream-prs.md`: `a6ccd45` and `96ab887`.
- No GPU code. Model output changes only for images that previously decoded
  wrong, were rejected, or read past their luma plane.
