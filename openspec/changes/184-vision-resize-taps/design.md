# Design

## Context

`ds4_resize_bicubic_rows` computes, per output pixel:
- the clamped source window;
- the x and y cubic weights inside the double loop;
- a normalized, rounded, clamped sum.

`ds4_resize_rgb_bicubic` splits output rows over `min(work / 65536, 8)`
threads. The PR's base had no threads.

Tabulating the weights keeps every product and every addition in the same
order. The value of each weight is the same expression on the same inputs. A
bitwise difference can still come from the compiler: under `-ffast-math` the
inlined `ds4_cubic` in the old loop and the table fill in the new one may be
contracted (FMA) or reassociated differently. That is what the author saw on
znver4. Only a measurement on the child's toolchain and flags decides.

## Decisions

### D1. Bitwise gate first, before any speed work

A scratch harness, `$SCR/c184/resize_diff.c`:
- it holds a verbatim copy of `main`'s `ds4_resize_bicubic_rows` and the
  ported one;
- it is built with the Makefile's `CFLAGS` (`-O3 -ffast-math -mcpu=native`);
- it compares the float canvases with `memcmp`.

The corpus is built so that rounding decides the result, as the PR's was:
- two-level checkerboards and stripes at exact and near-exact integer ratios;
- downscales and upscales (Qwen's `smart_resize` upscales below its minimum
  pixel count);
- 1xN and Nx1 sources and targets;
- the decoder's limit dimensions;
- the `smart_resize` targets of 4032x3024, 3024x4032, 1920x1080, 1280x720,
  640x480, 200x2000 and 32x32 at the default min and max image tokens;
- random photographs-like noise at the same geometries.

At least 400 geometries in all. One differing float on any geometry drops the
change: restore `main`'s file, record the geometry and the count.

The harness also runs the threaded path (worker counts 1, 2 and 8) so that the
row split cannot hide a difference.

### D2. Tables built once, shared by the workers

`ds4_resize_rgb_bicubic` builds `xtaps`/`ytaps` before the threads, puts
pointers to them in `ds4_resize_rows`, and frees them after the join. The
workers only read them. An allocation failure returns 0 before any thread
starts. The Qwen call site frees the canvas and reports "unable to resize
image", as the PR does for its call sites.

### D3. Speed (CPU)

Time `ds4_image_preprocess_qwen4` alone, `main` against the branch, in ABBA
pairs, 20 pairs per image, on 4032x3024, 1920x1080 and 640x480 synthetic
images: pooled bootstrap 95% CI of the wall time. Kept if one size's CI lies
wholly below zero and none lies wholly above. A neutral result drops it: it
adds about 60 lines.

For scale, report the same images' vision encode time from one Q4 run of the
vision gate. If preprocessing is a negligible share of an image request, say
so in the report; the rule above still decides.

### D4. GPU guards

A bitwise-identical canvas gives identical encoder input, so model output
cannot change. Once at the end, as for any performance change:
- `tests/model_gates.sh` on Q4 with the mmproj and the `orbit`/`maple`
  fixtures (its vision gate);
- `tools/parity-check.sh`;
- one `ab_bench.py --bitwise` row for the record.

None of these measures the gain; D3's figures go in the commit message.

## Risks / Trade-offs

- **Flags drift:** a later toolchain or flag change could break identity
  that holds today. Keep `resize_diff.c` as an in-tree model-less test only if
  the owner wants it; by default it stays in `$SCR` and the flat-image test
  is the in-tree check.
- **Memory:** two tables of `dst_n * max_taps` doubles each, a few hundred KB
  at the largest Qwen canvas.
