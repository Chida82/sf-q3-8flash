# Tasks

GPU: sections 1 to 4. Starts after `190-ssd-capped-ram-bench` has landed.
Model runs are strictly sequential; a process that opens a GGUF is a model
run; every model run is under the one-second memory guard. `$SCR` is
`~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c191/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal; streamed equals
resident, token gate, on Q4.

## 1. S0, the probe (design D1)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/191-ssd-decode-layer-round-trip`. Read every caller of `ds4_gpu_qwen4_moe_stream_tensor` and of the drain with `rg`; confirm the five steps of the design's context on the code, and correct the design where they differ.
- [ ] 1.2 Scratch probe on a worktree (never committed): the four timestamps per row-path call with its miss count. Q4, capped at the development footprint, `capped-mtp-code` and `capped-plain`.
- [ ] 1.3 The table (wake, lookup, encoding, start; all cached against missing) and the projection of S1 to S3 in `$SCR/c191/steps.txt`. Close the change by D1 if under 2%.

## 2. S1, commit the expert pass without waiting (design D2)

- [ ] 2.1 The flush behind `DS4_QWEN4_STREAM_FLUSH_EXPERTS=0`; a model-less case that a flushed pass's entries are not evicted before it completes.
- [ ] 2.2 The step checks, the switch on and off.
- [ ] 2.3 Measure by D3. Keep or drop.

## 3. S2, the bounded poll (design D2)

- [ ] 3.1 The poll behind `DS4_QWEN4_STREAM_DRAIN_POLL=0`; the bound from 1.3.
- [ ] 3.2 The step checks, the switch on and off.
- [ ] 3.3 Measure by D3 against the state after section 2. Keep or drop.

## 4. S3, the ids through a shared buffer (design D2; only if 1.3 shows the lag)

- [ ] 4.1 The copy kernel and the CPU poll, with S2's poll as the fallback; a CPU-reference comparison of the copied ids is not needed (integers), a mismatch check against `ds4_gpu_tensor_read` in the test is.
- [ ] 4.2 The step checks, the switch on and off.
- [ ] 4.3 Measure by D3 against the state after section 3. Keep or drop.

## 5. Review and closing

- [ ] 5.1 Final pass: remove the switches of kept steps unless a measurement says a step is machine dependent; delete what the change made dead.
- [ ] 5.2 The final state against `main` at 48, 54 and 60 GiB and once with the RAM free (design D3); a resident record row against the segment start.
- [ ] 5.3 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`.
- [ ] 5.4 `docs/SSD_STREAMING.md`: the layer round trip and what each kept step removed. Tell `189` which state it measures against (design D4).
- [ ] 5.5 `openspec validate 191-ssd-decode-layer-round-trip --strict` passes.
- [ ] 5.6 Report to the user in Italian. Land as one signed commit; delete `$SCR/c191/`; archive the change.
