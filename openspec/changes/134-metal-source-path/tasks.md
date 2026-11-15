# Tasks

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`. Model
runs strictly sequential.

## 1. Change

- [ ] 1.1 `ds4_gpu_full_source`: search the executable's directory, then its parent; keep the overrides; drop cwd (design D1). Mark the site.
- [ ] 1.2 `make -j8` without warnings; `make test -j8`; `make test-qwen4-kernels`.

## 2. Proof (design D2)

- [ ] 2.1 The mixed-cwd run loads the binary's own kernels, and its tokens equal the same-tree run.
- [ ] 2.2 `tests/model_gates.sh` on Q4; parity `PARITY OK`; `ab_bench.py --bitwise -m <Q4>` against `main`.

## 3. Closing

- [ ] 3.1 `docs/METAL.md`; the `AGENTS.md` traps list.
- [ ] 3.2 `openspec validate 134-metal-source-path --strict`.
