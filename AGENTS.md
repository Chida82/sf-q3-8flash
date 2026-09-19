# sf-q3-8flash — contributor and agent guide

This repository is the self-contained **Qwen3.8 Flash Next / Apple Metal**
child of [StarForge](https://github.com/Chida82/StarForge), forked from
[ds4 / DwarfStar](https://github.com/antirez/ds4). Work here directly; the
StarForge checkout is needed only for upstream-sync and parity tooling.

Read this file first. Read `AGENT.md` for implementation-quality rules and the
relevant document under `docs/` before changing a subsystem.

## Product contract

| Item | Contract |
|---|---|
| Model | Qwen3.8 Flash Next (`qwen4exp`) only |
| Shapes | `DS4_SHAPE_QWEN4_EXP`; `DS4_SHAPE_QWEN4_MINI` only for synthetic tests |
| Backend | Apple Metal only; CPU remains a reference and model-less test path |
| Binaries | `sf-q3-8flash`, `sf-q3-8flash-server`, `sf-q3-8flash-bench`, `sf-q3-8flash-eval` |
| Default model | `qwen3.8-flash-next.gguf` |
| Server port | `8004` |
| Home / lock | `~/.sf/q3-8flash`; `/tmp/sf-q3-8flash.lock` |
| Vision | Qwen3-VL projector supported |
| Speculation | Built-in Qwen MTP (`--mtp`); no external support model or DSpark |
| Steering | `--dir-steering-file`, FFN/attention scales, `/steer`, `dir-steering/` |
| Distributed | TP/RDMA/pipeline plumbing stays, even where Qwen currently rejects a mode |

Do not add `ds4-agent`, CUDA, ROCm, another model, or generic model-selection
layers. External coding agents talk to `sf-q3-8flash-server`; see
`docs/CLIENTS.md`.

## Start work

```sh
git status --short --branch
git config rerere.enabled true
git switch -c fix/<topic>       # or perf/<topic>, feature/<topic>
make -j8
make test -j8
```

Never work on `main`. Never commit or push unless the user explicitly asks.
Before editing a function, find every caller with `rg`; fix shared root causes
once rather than patching one frontend.

## Where Qwen work lives

- `ds4.c`: GGUF validation, Qwen tokenizer/chat template, CPU reference,
  Qwen graph/session state, built-in MTP, snapshots, scheduling.
- `ds4_metal.m`: Metal runtime and Qwen kernel wrappers.
- `metal/qwen4.metal`: text/MTP kernels.
- `metal/qwen4_vision.metal`, `ds4_qwen4_vision.h`, `ds4_image.*`: vision.
- `ds4_cli.c`, `ds4_server.c`, `ds4_bench.c`, `ds4_eval.c`: product surfaces.
- `ds4_tp.*`, `ds4_distributed.*`: transport and distributed execution.
- `ds4_ssd.*`: SSD-backed model data; Qwen's large BF16 n-gram table is read
  directly from the GGUF.
- `ds4_qwen4_unicode.inc`: generated tokenizer classes; regenerate with
  `gguf-tools/gen_qwen4_unicode.py`, do not hand-edit.
- `gguf-tools/qwen4_*`: conversion and packing.
- `tests/test_qwen4_*`: focused model, MTP, state, steering, and vision tests.

Historical internal names such as `glm_mtp` may still carry the shared built-in
MTP switch. Do not rename `ds4_*` files, `ds4_` symbols, or `DS4_*` environment
variables: preserving upstream identity keeps merges reviewable.

## Development loop

Use the smallest check that covers the change, then widen it:

```sh
make -j8                         # no warnings
make test -j8                    # model-less regression suite
make test-qwen4-kernels          # kernel changes
make test-qwen4-q2               # low-bit expert changes
make test-qwen4-prefill-reuse    # prefill or graph-state changes
make test-qwen4-ngrams           # tokenizer / n-gram changes
python3 tests/test_model_download.py
```

For vision changes, run the model-less Python metric tests first, then
`make test-qwen4-vision` with `DS4_QWEN4_SNAPSHOT`, `DS4_QWEN4_MMPROJ`, and
`DS4_QWEN4_IMAGE`. For server changes, always run `./ds4_test --server`; add the
smallest existing server integration test matching the changed protocol.

Before a PR, when local GGUFs exist:

```sh
make mtp-verify-depth DS4_TEST_MODEL=/absolute/path/model.gguf
./sf-q3-8flash-eval -m /absolute/path/model.gguf --suite core
./sf-q3-8flash-bench -m /absolute/path/model.gguf
```

Then run the StarForge parity oracle from the orchestrator checkout:

```sh
tools/parity-check.sh sf-q3-8flash /absolute/path/model.gguf
```

Parity means greedy output is token-identical to upstream at the merge-base and
throughput stays within 2%. Do not download a 137+ GiB model merely to run a
routine unit test; use an existing local GGUF or ask first.

## Correctness rules

- Preserve Qwen's GDN/GQA cadence, recurrent state, block-sparse index state,
  hyper-connections, disk-backed BF16 n-grams, and MTP rollback boundaries.
- A kernel optimization needs one CPU-reference comparison covering its edge
  sizes. Do not accept unexplained logits or state drift for speed.
- Snapshot format changes need save/load, rewind, truncated-input, and reused
  session coverage. Keep old-format compatibility unless the user explicitly
  approves a format break.
- Server changes must preserve OpenAI, Responses, Anthropic, and completions
  endpoints plus exact tool-call continuation and disk-KV validation.
- Never run two huge model processes concurrently. Keep `DS4_*` toggles inline,
  for example `DS4_METAL_CB_TIMES=1 ./sf-q3-8flash ...`; never export them.
- Do not simplify away validation at GGUF, HTTP, filesystem, or snapshot trust
  boundaries.

## Child and upstream discipline

- Delete unreachable foreign-model/backend code; do not hide it behind a new
  `#ifdef`. In a retained file, mark a non-obvious cut at the exact site:
  `/* sf-ablate(<area>): <removed behavior; Qwen/Metal reason> */`.
- If uncertain code may be shared with Qwen, keep it temporarily with
  `/* sf-keep: <reason and revisit condition> */` and test before removal.
- Docs describe only this child. Delete stale paragraphs rather than rewriting
  upstream text into a different promise.
- For upstream updates, follow StarForge `SYNC.md`: fetch `upstream`, merge on
  `sync/<sha7>`, let rerere help, never use `-X ours/theirs`, test, update
  `TRACE.md`, and run parity. `TRACE.md` is only for upstream-sync reasoning.
- Stop and ask if upstream renamed/split a `ds4_*` file, a conflict changes
  shared Qwen numerics, or model-less tests pass while parity fails.
