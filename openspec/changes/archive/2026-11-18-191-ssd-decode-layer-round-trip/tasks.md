# Tasks

GPU: sections 1 to 4. Starts after `190-ssd-capped-ram-bench` has landed.
Model runs are strictly sequential; a process that opens a GGUF is a model
run; every model run is under the one-second memory guard. `$SCR` is
`~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c191/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal; streamed equals
resident, token gate, on Q4.

## 1. S0, the probe (design D1)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/191-ssd-decode-layer-round-trip`. Read every caller of `ds4_gpu_qwen4_moe_stream_tensor` and of the drain with `rg`; confirm the five steps of the design's context on the code, and correct the design where they differ. *(The five steps hold on `main`. Decode runs inside one command batch (`qwen4_graph_begin_commands_if_needed`), so the drain at step 1 is `ds4_gpu_end_commands` -> `ds4_gpu_finish_command_buffer`, which waits the flushed buffers first and then the batch with `waitUntilCompleted`. Callers: `qwen4_graph_moe_impl` only, and the unit test.)*
- [x] 1.2 Scratch probe on a worktree (never committed): the four timestamps per row-path call with its miss count. Q4, capped at the development footprint, `capped-mtp-code` and `capped-plain`. *(Probe on the scratch worktree `191-probe` (`$SCR/c191/probe191.py`), 2 runs per kind; the same build counted the owned-path calls for `193`.)*
- [x] 1.3 The table (wake, lookup, encoding, start; all cached against missing) and the projection of S1 to S3 in `$SCR/c191/steps.txt`. Close the change by D1 if under 2%. *(Medians per call, us, all cached / missing. capped-mtp-code: wake 67.7 / 69.7, lookup 13.2 / 761.9, expert encode 8.9 / 8.1, rest of the layer to the next commit 12.4 / 12.9, commit to GPU start 94.2 / 92.5. capped-plain: 65.3 / 66.5, 11.7 / 664.7, 8.3 / 7.5, 12.6 / 12.2, 93.9 / 90.0. Over decode: wake 6.1% (MTP code) and 8.2% (plain), commit start 8.3% and 10.1%. The CPU encodes the rest of a layer and the next router in about 12 us, so S1 has nothing to hide and would add a commit whose start costs about 92 us: dropped by D2 without being built. S2 projects to at most 5.8% (MTP code) and 7.6% (plain) of decode: the change continues. Drain span from commit to GPU end: p50 463 us, p99 1565 us.)*

## 2. S1, commit the expert pass without waiting (design D2)

- [x] 2.1 The flush behind `DS4_QWEN4_STREAM_FLUSH_EXPERTS=0`; a model-less case that a flushed pass's entries are not evicted before it completes. *(Not built: S1 dropped by D2 on the figures of 1.3.)*
- [x] 2.2 The step checks, the switch on and off. *(Not run: S1 not built.)*
- [x] 2.3 Measure by D3. Keep or drop. *(Dropped.)*

## 3. S2, the bounded poll (design D2)

- [x] 3.1 The poll behind `DS4_QWEN4_STREAM_DRAIN_POLL=0`; the bound from 1.3. *(Built: in `ds4_gpu_wait_command_buffer`, a spin on `cb.status` bounded at 2 ms (the drain p99 of 1.3 is 1.6 ms), armed only around the drain of a row-path call; removed after 3.3.)*
- [x] 3.2 The step checks, the switch on and off. *(make -j8 no warnings; make test green; test_qwen4_ssd_experts PASS with the poll on, off and with uncached reads; streamed equals resident on Q4 (`ab_bench.py`, plain and both MTP kinds, PASS (tokens)); resident against `main` PASS (tokens; bitwise).)*
- [x] 3.3 Measure by D3 against the state after section 2. Keep or drop. *(DROPPED. capped-mtp-code at 54 GiB, A = `main` 5518046, one invocation: decode A 29.67-29.95 t/s, B 25.37-25.54 (-15%, 4 pairs, every one); prefill unchanged (776-786 both). The B runs ran the GPU at 716-734 MHz and 7-8 W against 1580-1590 MHz and 25-30 W: while the decode thread spins instead of blocking in `waitUntilCompleted`, the GPU stays at a low clock. The harness flagged all four pairs as disturbed by frequency; the disturbance is the step itself. The other two kinds and the second invocation were not run: the loss is five times the A/A resolution and its cause is the mechanism, not the kind.)*

## 4. S3, the ids through a shared buffer (design D2; only if 1.3 shows the lag)

- [x] 4.1 The copy kernel and the CPU poll, with S2's poll as the fallback; a CPU-reference comparison of the copied ids is not needed (integers), a mismatch check against `ds4_gpu_tensor_read` in the test is. *(Not built. S0 cannot separate the completion lag from the wake, and both S3 and its fallback wait by polling, which 3.3 showed lowers the GPU clock.)*
- [x] 4.2 The step checks, the switch on and off. *(Not run.)*
- [x] 4.3 Measure by D3 against the state after section 3. Keep or drop. *(Dropped.)*

## 5. Review and closing

- [x] 5.1 Final pass: remove the switches of kept steps unless a measurement says a step is machine dependent; delete what the change made dead. *(No kept step: the code equals `main`. The scratch probe was never committed.)*
- [x] 5.2 The final state against `main` at 48, 54 and 60 GiB and once with the RAM free (design D3); a resident record row against the segment start. *(Nothing to measure: no code changes.)*
- [x] 5.3 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`. *(Not needed: no code changes (docs and the change record only).)*
- [x] 5.4 `docs/SSD_STREAMING.md`: the layer round trip and what each kept step removed. Tell `189` which state it measures against (design D4). *(The round trip table and the two dropped steps in "Capped RAM". For `189`: it measures against `main` as it is, since nothing of this change landed in code; the handshake parks the GPU on a CPU-signalled event, so its CPU side must not spin either.)*
- [x] 5.5 `openspec validate 191-ssd-decode-layer-round-trip --strict` passes.
- [x] 5.6 Report to the user in Italian. Land as one signed commit; delete `$SCR/c191/`; archive the change. *(Landed as one signed commit, docs and record only.)*
