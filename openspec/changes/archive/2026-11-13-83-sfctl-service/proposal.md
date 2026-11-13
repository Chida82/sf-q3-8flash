# Proposal

## Why

`sf-ds4-1flash` runs its model as an on-demand launchd service through
`sfctl` (its change `675-sfctl`). The script was written to be model-agnostic,
so every child could carry the same copy with only its own `.conf`, and the
StarForge registry already reserves sfctl port 8912 for this child. This child
has no `sfctl/` yet: the owner starts `sf-q3-8flash-server` by hand, from
whatever branch the checkout is on, and cannot switch between the two models
with one command.

Two things stand in the way of a plain copy:
- `sf-ds4-1flash`'s `sfctl/README.md` and `tests/test_sfctl.sh` name that model,
  its port and its boost daemon, so a copy would have to be adapted by hand in
  each child and would drift at the next fix;
- `download.sh`, which `sfctl install` calls to link the GGUFs, reads the cache
  path from `hf download`'s stdout. `hf` 2.4 detects an AI agent and prints
  hints followed by `path=<file>` instead, so an agent-run install stops at the
  model links.

## What Changes

- **`sfctl/` in this child.**
  - `sfctl/sfctl`: the `sf-ds4-1flash` script, unchanged except its usage line,
    which no longer names that model.
  - `sfctl/sf-q3-8flash.conf`: this model's service, described in a comment
    block at its top.
  - `sfctl/README.md`: made model-agnostic (examples use `<model>` and
    `<port>`; the service description lives in the config's comments; boost is
    described as any `--boost*` option).
- **The service** (`sf-q3-8flash.conf`):
  - port 8912 on 127.0.0.1;
  - Q4 weights resident, about 70 GiB, no SSD streaming;
  - the Qwen3-VL projector (`--vision`);
  - `--ctx 262144 --tokens 65536`, the native context;
  - `--mtp --mtp-exact-sampling`: greedy output and the sampling distribution
    stay those of a plain run (no precision loss);
  - disk KV in `~/.sf/q3-8flash/kv`, 32 GiB.
- **A shared test.** `tests/test_sfctl.sh` reads the model, server and port
  from the checkout's only `sfctl/sf-*.conf`, so it is the same file in every
  child; it runs in `make test` and as `make test-sfctl`.
- **`download.sh`** takes the last line of `hf download`'s output and drops a
  `path=` prefix. `tests/test_model_download.py` gains an agent-mode case.
- **Docs.** `README.md` gets a paragraph on running as a service; `AGENTS.md`
  gets a Service row and a "Serving (sfctl)" section that says which three
  files are shared and which one is this model's.
- **In `sf-ds4-1flash`** (its own commit): the same three shared files, so
  they are byte-identical in both children; its service description moves from
  `sfctl/README.md` into the comments of `sfctl/sf-ds4-1flash.conf`.

Non-goals:
- no master copy of the script in the StarForge orchestrator;
- no change to the engine, the server or any default;
- no SSD streaming or boost for this model's service.

## Capabilities

### New Capabilities
- `service-control`: how this model is installed, run, stopped, inspected,
  synced to main and removed as an on-demand local service through `sfctl`,
  from a serve worktree at local `main`.

### Modified Capabilities
(none)

## Impact

- **New files:** `sfctl/sfctl`, `sfctl/README.md`, `sfctl/sf-q3-8flash.conf`,
  `tests/test_sfctl.sh`.
- **Edited:** `Makefile` (test rules), `README.md`, `AGENTS.md`, `download.sh`,
  `tests/test_model_download.py`.
- **On the machine, only when `install` runs:** a worktree at
  `~/.sf/q3-8flash/serve`, the LaunchAgent `com.starforge.sf-q3-8flash`, logs
  under `~/Library/Logs/sf/`, and the `~/.local/bin/sfctl` link (shared by
  every installed child, since the script is identical).
- **Speed and output:** unchanged; no A/B run and no parity oracle.
