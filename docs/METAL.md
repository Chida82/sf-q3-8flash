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

Set diagnostics inline, never globally:

```sh
DS4_METAL_CB_TIMES=1 ./sf-q3-8flash -p "Hello"
```

Use `make test-qwen4-kernels` after Metal or kernel changes and run model-backed
parity before landing performance work.
