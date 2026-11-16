# Proposal

## Why

Qwen3-VL preprocessing resizes every image whose size differs from its
`smart_resize` target with `ds4_resize_rgb_bicubic` (`ds4_image.c:402`,
called at `:487`). The inner loop calls `ds4_cubic()` once per contributing
source pixel, although a tap weight depends only on the output coordinate and
the source sample. A 12 MP photo evaluates the kernel hundreds of millions of
times for a few thousand distinct values. Preprocessing runs synchronously
before the vision encode, so this is latency on every image request.

#1008 (`7d14832`, one commit) builds one weight row per output sample, once,
and accumulates with the same products and sums in the same order. The author
reports about 2x on an x86 single-threaded build:
- 4032x3024 to the DeepSeek canvas: 283 -> 140 ms;
- 1280x720: 36 -> 19 ms.

The author also reports zero differing floats over 457 geometries at every
flag set tried except one: `-O3 -ffast-math -march=native` on znver4, where
one geometry moved 48 values by one level. The child builds with
`-O3 -ffast-math -mcpu=native`, the same kind of combination, on arm64. So
identity here is not known until it is measured. Performance under the intake
criteria, conditional on bitwise identity.

The child's resize differs from the PR's base: it splits output rows across up
to 8 threads (`ds4_resize_bicubic_rows`). The tables must be built once,
before the threads start, and shared read-only. The ~2x figure is
single-threaded and must be re-measured here.

## What Changes

- Port `7d14832` onto the threaded resize: build the x and y tap tables in
  `ds4_resize_rgb_bicubic`, pass them to the row workers, and free them after
  the join. The resize returns failure when the tables cannot be allocated,
  and `ds4_image_preprocess_qwen4` turns that into its error. The GLM and
  DeepSeek call-site hunks have no target here.
- The PR's test is DeepSeek-only (`test_deepseek4_vision_image.c`, not in the
  child). Add its flat-image property to `tests/test_image_decode.c` against
  `ds4_image_preprocess_qwen4` instead: a uniform image stays uniform.
- **Gate:** a bitwise canvas comparison, old against new, over a geometry
  corpus, built with the child's flags on this machine. Any differing float
  drops the change (design D1).
- #1013 (`bab5b5a`, separable two-pass filter) is not part of this change. Its
  author shows it moves .5 rounding ties by one level on 13 of 457 geometries,
  so it changes pixels.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: preprocessing speed only; the canvas is bitwise identical or the change is dropped)

## Impact

- `ds4_image.c` (`ds4_resize_rgb_bicubic`, `ds4_resize_bicubic_rows`, the Qwen
  call site's error path), `tests/test_image_decode.c`.
- `docs/upstream-prs.md` (`7d14832`; #1013 drop).
