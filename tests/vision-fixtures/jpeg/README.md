# JPEG decoder fixtures

The two `prog_ac_refine_zrl_*` images exercise successive-approximation AC refinement (`Ss=1, Se=63,
Ah=2, Al=1`) with restart markers. The unpatched Iris decoder mishandles ZRL
(`run=15, size=0`) in that scan: it keeps consuming correction bits after the
16th currently-zero coefficient.

Generated with libjpeg-turbo 3.2.0 `cjpeg`. Re-run `./generate.sh` if you have
`cjpeg` on `PATH`.

The sampling-factor fixtures were added later with libjpeg-turbo 2.1.5 `cjpeg`,
which regenerates the two ZRL files byte for byte. The `*_luma_subsampled`
files sample luma below Cb (`-sample 1x1,2x2,1x1`), so the Y plane is smaller
than the image. The other two exercise non-interleaved scans (one component per
scan), whose blocks come in raster order rather than grouped by MCU (ITU T.81
A.2.2).

| File | Size | Why it is here |
| --- | --- | --- |
| `prog_ac_refine_zrl_gray.jpg` | 24x16 grayscale | Unpatched decode succeeds but pixels differ from libjpeg-turbo. Patched decode is bit-exact with `djpeg`. |
| `prog_ac_refine_zrl_420.jpg` | 64x48 YCbCr 4:2:0 | Unpatched `jpeg_load` returns NULL. Patched decode is bit-exact with `djpeg`. |
| `base_luma_subsampled.jpg` | 40x24 YCbCr baseline, sampled 1x1,2x2,1x1 | Unpatched decode reads the 24x16 Y plane as if it were 40x24, past its end (AddressSanitizer: heap-buffer-overflow). Patched decode is bit-exact with `djpeg`. |
| `prog_luma_subsampled.jpg` | 40x24 YCbCr progressive, sampled 1x1,2x2,1x1 | Same read past the Y plane on the progressive path. Patched decode is bit-exact with `djpeg`. |
| `prog_dc_per_component_420.jpg` | 48x32 YCbCr 4:2:0, one DC scan per component (first and refinement) | Unpatched decode reads the 2x2 luma DC blocks in MCU order and gets different pixels. Patched decode is bit-exact with `djpeg`. |
| `base_gray_2x2.jpg` | 40x24 grayscale baseline, 2x2 sampling factors | Unpatched `jpeg_load` returns NULL. Patched decode is bit-exact with `djpeg`. |
| `prog_sos_se_oob.jpg` | progressive, AC scan with `Se=200` | Reproducer bytes from upstream issue #1292, not produced by `generate.sh`. Unpatched decode indexes `jpeg_zigzag[]` past 63; patched `jpeg_load` rejects the scan header. |

`make test` covers all of them through `tests/test_image_decode`.
