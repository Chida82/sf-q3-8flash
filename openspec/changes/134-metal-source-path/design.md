# Design

## Decisions

### D1. Executable directory, then its parent; no cwd

Take the executable's path with `_NSGetExecutablePath` and resolve it with
`realpath`, so symlinks and relative launches resolve to the real tree. The
search order for each kernel file is:
1. the file's `DS4_METAL_<NAME>_SOURCE` override, when set;
2. `<exe dir>/metal/<file>`;
3. `<exe dir>/../metal/<file>`.

A file found in none of them is an error, and the message lists the paths it
tried.

Rejected:
- **Kernels compiled into the binary:** the largest divergence from upstream,
  and it needs a build step for every kernel edit.
- **A build-time fingerprint check:** it keeps the cwd lookup and only turns
  the mixed build into an error.
- **Keeping cwd as a last fallback:** that brings the trap back for a binary
  run outside any tree.

### D2. Proof

- A run of the main checkout's binary with cwd in another worktree (for
  example `seg1-91f225a`) logs `// appended <main checkout>/metal/...`. Its
  greedy tokens equal the same binary run from its own tree.
- `make test -j8`, `make test-qwen4-kernels`, `tests/model_gates.sh` on Q4.
  Parity `PARITY OK`; `ab_bench.py --bitwise -m <Q4>` against `main`. It runs
  each build in its own tree, so it must still pass bitwise.
- `sfctl` serve: the binary in `~/.sf/q3-8flash/serve` finds its own
  `metal/`, so no change there. Check it at the next serve sync.
