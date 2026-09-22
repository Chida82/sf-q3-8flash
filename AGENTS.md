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

`make cpu` links the CPU-reference build over the same four binary names, so a
model-backed run straight after it fails with "requires Metal or single-GPU
CUDA". Rebuild with `make` before touching the model.

For vision changes, run the model-less Python metric tests first, then
`make test-qwen4-vision` with `DS4_QWEN4_SNAPSHOT`, `DS4_QWEN4_MMPROJ`, and
`DS4_QWEN4_IMAGE`. For server changes, always run `./ds4_test --server`; add the
smallest existing server integration test matching the changed protocol.

Before a PR, when local GGUFs exist:

```sh
DS4_TEST_MODEL=/absolute/path/model.gguf DS4_TEST_GLM_MTP=1 ./ds4_test
python3 tests/test_qwen4_mtp_limits.py --model /absolute/path/model.gguf
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
  `sync/<sha7>`, let rerere help, never use `-X ours/theirs`, test, and run
  parity. Sync reasoning lives in the `sf-ablate`/`sf-keep` markers at the cut
  and in the commit message, never in a separate ledger.
- Stop and ask if upstream renamed/split a `ds4_*` file, a conflict changes
  shared Qwen numerics, or model-less tests pass while parity fails.

## Why this repository keeps shrinking

The point of a child is not only a smaller binary. It is a source tree that an
agent (or a person) can load, read and reason about with the fewest tokens
possible, so that Qwen3.8-specific optimisation work is cheap and safe. That
goal is weighed against sync cost: every removed line is a divergence from
upstream that `git merge upstream/main` will bring back as a conflict, and
`git rerere` only replays a resolution when the conflict text is identical.
Whole dead functions repay that cost many times over (tens or hundreds of
lines per conflict site). Scattered dead conditionals do not, and the
compiler already drops them from the binary; remove them only when the
token saving is real and the site is not interleaved with preprocessor
directives that break mechanical tools.

## Names that lie: do not remove by name, verify by reachability

Upstream grew several models in one tree, so many identifiers carry the name
of the model they were written for, not of the code they now serve. The list
below is what this child has established so far. At a sync, take upstream
fixes to these even when the name looks foreign; at an ablation, never delete
them on the strength of the name alone.

| Name family | What it really is | Evidence |
|---|---|---|
| `glm_graph_*`, `glm_gpu_graph`, `glm_dense_*`, `glm_debug_*` | the shared Metal graph host: workspace, tensor views, env toggles, matmul wrappers. Qwen3.8 runs on it | ~1,200 references remain after every GLM-5.3 branch was removed; the build depends on them |
| `glm_mtp`, `glm_mtp_timing`, `glm_mtp_have` | the built-in MTP switch. `--mtp` sets `engine.glm_mtp`; Qwen speculation is off without it | `ds4_cli.c` `--mtp` handler; `ds4_session_eval_speculative*` Qwen branch |
| `spec_frontier_*`, `metal_graph_dspark_cache_*`, `g->dspark_cache_*` | snapshot/rollback frontier used by `ds4_session_tp_spec_cycle` (TP plumbing, SPEC.md §B). Qwen's own `--mtp` path never reaches it | runtime probes: zero hits with `--mtp`, with depth pinned to 2, and with `DS4_MTP_FORCE_SNAPSHOT` |
| `dspark_exact_sampling` | the `--mtp-exact-sampling` flag for built-in MTP; not DSpark | `ds4_cli.c`, `ds4_server.c` handlers |
| `dsv4_*.metal`, `kernel_dsv4_*` | DeepSeek-derived kernels that the Qwen graph reuses (hc, kv, rope, misc) | every kernel in those files is referenced from `ds4_metal.m` |
| `metal/*.metal` kernels that no string literal names | usually template bodies, instantiated through `typedef decltype(...)` plus `template [[host_name("...")]] kernel alias_t body<...>;` | a search for `"kernel_x"` misses them; check `\bkernel_x<` and `decltype(kernel_x` before calling a kernel dead. Every name reaches `newFunctionWithName:` from a literal or a switch of literals, so the formable set is exactly the literal set plus the four `kernel_flash_attn_ext_*` format patterns; after that audit only 11 instantiations were dead |
| `ds4_deepseek4_attention_bounds` and the `deepseek4.*` GGUF key readers | shared attention-bounds helper and metadata readers | called from the Qwen path |

When in doubt, prove it: build with the symbol removed, or add a one-line
`fprintf` probe and run the model. A probe result outranks any name.

## Misleading-name traps that already cost time

- `make cpu` links the CPU-reference build over the same four binary names;
  the next model-backed run then fails with "requires Metal or single-GPU
  CUDA". Rebuild with `make` first.
- `mtp-verify-depth` (removed) exercised the external MTP support model, not
  built-in MTP, so it could only skip or fail here.
- A preprocessor-output diff (`cc -E -P` before/after) cannot see the removal
  of `#error`/`#warning` guards or of `#else` fallbacks whose condition is true
  in the tested configuration. Check those with a negative compile, never with
  the oracle alone.
- The Metal shader compiler cannot report dead device code from inside the
  process: on a successful compile `newLibraryWithSource:` leaves `error` nil,
  so warnings never surface (verified with a deliberately unused probe
  function and an injected `-Wunused-function` pragma). `MTLCompileOptions`
  takes no warning flags and `xcrun metal` is not in the Command Line Tools.
  For kernels the only oracle is the host: the set of names `ds4_metal.m` can
  form; for device helpers there is none short of installing Xcode.
