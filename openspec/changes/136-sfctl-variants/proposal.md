# Proposal

## Why

The q3-8flash service runs Q4 only, through the root default link
`qwen3.8-flash-next.gguf`. The owner also wants to serve Q2 (about 42 GiB
resident against Q4's 70 GiB), and that link is unfit for a service: it
changes during test and development (`./download.sh q2` re-points it), so
what the service runs is in doubt.

## What Changes

- `sfctl` learns **variants**: one service per model, several sets of weights.
  A config lists `SF_VARIANTS` and one `SF_MODEL_<variant>=component:path`
  each; the service name `<model>-<variant>` selects one.
- `start` of a model with variants needs `<model>-<variant>`; `start` of
  another variant while one runs is refused with the `restart` to run;
  `restart <model>-<variant>` switches. Other commands take either name.
- `start` writes the variant's agent, passing its model with `-m`, and records
  the variant under `~/.sf/<model>/variant`; `status` shows it.
- `@VARIANT@` in `SF_ARGS` gives each variant its own disk KV cache.
- `install` and `update` link every variant's model; `start` links nothing.
- `sf-q3-8flash.conf` declares `q4` and `q2`, both on the fixed per-quant
  links, with KV in `~/.sf/q3-8flash/kv-<variant>`.
- A config without variants writes the same agent as before, byte for byte.
- `update` hands over to the `sfctl` it checked out, so build, links, agent
  and restart always follow `main`'s logic.

## Impact

- `sfctl/sfctl`, `sfctl/README.md`, `tests/test_sfctl.sh`: shared by every
  child; copy them unchanged.
- `sfctl/sf-q3-8flash.conf`, `AGENTS.md`, `README.md`.
- `openspec/specs/service-control`: variants, `-m`, KV per variant, update
  handover.
- On the machine, after `./sfctl/sfctl update q3-8flash` from the main
  checkout (once; serve's script predates the handover): Q2 is linked in
  serve, the agent is rewritten for Q4 with `-m`, and `~/.sf/q3-8flash/kv`
  stops being used (left in place).
