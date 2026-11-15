# Apple Metal

This child supports Apple Metal as its production backend. Install Xcode
command-line tools and run `make -j8`. The resulting binaries are
`sf-q3-8flash`, `sf-q3-8flash-server`, `sf-q3-8flash-bench`, and
`sf-q3-8flash-eval`.

Q2 needs roughly 42 GiB for resident weights; Q4 roughly 70 GiB. Context,
recurrent state, vision, batching, and temporary buffers require additional
memory. Start Q2 conservatively on a 64 GB Mac:

```sh
./sf-q3-8flash --ctx 8192 --prefill-chunk 1024
```

Kernels are read from `metal/*.metal` and compiled when the GPU starts. Each
file is looked up beside the running executable, then in its parent directory
(for the binaries built under `tests/`); the current directory is never
searched, so a binary always compiles its own tree's kernels wherever it is
run from. `DS4_METAL_<NAME>_SOURCE` (for example `DS4_METAL_QWEN4_SOURCE`)
overrides one file for a diagnostic run. A missing file is an error that names
the paths tried.

Set diagnostics inline, never globally:

```sh
DS4_METAL_CB_TIMES=1 ./sf-q3-8flash -p "Hello"
DS4_QWEN4_TIMING=2 ./sf-q3-8flash -p "Hello"
```

`DS4_QWEN4_TIMING=2` submits the work after each stage group (ple, hc_attn,
gdn, attn, hc_ffn, moe, moe_mid, moe_down, head) and reports the GPU time of
each: per chunk for prefill, and as the mean per pass over every 50 decode or
verify passes of the same size. `moe_mid` and `moe_down` are the expert
gate/up and down kernels. On the tiled prefill path they hold the routed
experts only, and the router, the shared expert and the reduce stay in
`moe`; on single-token decode and MTP verify (T <= 8) they also include the
shared expert, which runs as an extra slot; decode batches of 9 to 64 rows on
the grouped path are not split. With Q2_K down experts (the Q2 pack),
single-token decode and the 2- and 3-row MTP verify fold the down rows and the
weighted reduce into one kernel (`kernel_qwen4_moe_down_reduce`, each row with
its single-token arithmetic), so their down time is reported under `moe` and
`moe_down` reads 0; judge such a step on `moe,moe_down` together. The waits
slow the run, but its output is unchanged.

Use `make test-qwen4-kernels` after Metal or kernel changes and run model-backed
parity before landing performance work.
