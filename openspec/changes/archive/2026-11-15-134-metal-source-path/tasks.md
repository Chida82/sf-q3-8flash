# Tasks

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`. Model
runs strictly sequential.

## 1. Change

- [x] 1.1 `ds4_gpu_full_source`: search the executable's directory, then its parent; keep the overrides; drop cwd (design D1). Mark the site.
- [x] 1.2 `make -j8` without warnings; `make test -j8`; `make test-qwen4-kernels`.

## 2. Proof (design D2)

- [x] 2.1 The mixed-cwd run loads the binary's own kernels, and its tokens equal the same-tree run.
- [x] 2.2 `tests/model_gates.sh` on Q4; parity `PARITY OK`; `ab_bench.py --bitwise -m <Q4>` against `main`.

## 3. Closing

- [x] 3.1 `docs/METAL.md`; the `AGENTS.md` traps list.
- [x] 3.2 `openspec validate 134-metal-source-path --strict`.

## Results

- 1.2: `make -j8` no warnings; `make test -j8` all suites OK; `make test-qwen4-kernels` all passed.
- 2.1 (model-less): `tests/test_qwen4_kernels` run from a cwd whose `metal/qwen4.metal` is poisoned,
  and from a cwd with no `metal/`: all passed (it loads `<tree>/metal/` via the parent of `tests/`).
  The binary copied to a directory with no `metal/` beside or above it fails with
  `Metal source metal/flash_attn.metal not found; tried <dir>/metal/..., <parent>/metal/...`.
- 2.1 (Q4, greedy, 96 tokens, code prompt): this branch's CLI from its own tree, from prev-main
  (main 698adf8) and from the poisoned cwd, and main's CLI from its own tree and from this tree:
  five identical outputs (md5 cc68dac0). main's CLI from the poisoned cwd fails to compile the
  kernels: the old binary takes the cwd's `metal/`, the new one never does.
- 2.2: `tests/model_gates.sh` on Q4 with mmproj and the two qwen38 fixtures: all PASS
  (mtp-identity 140 s, mtp-limits, mtp-turns, ds4_test, vision, host-paths).
  `SF_CHILD_DIR=<worktree> tools/parity-check.sh sf-q3-8flash <Q4>`: PARITY OK, 10 prompts,
  against upstream b3f5018. `ab_bench.py --bitwise -m <Q4>` against main: correctness PASS
  (tokens; bitwise), 11 pairs; every speed range straddles zero (host change at startup only).
