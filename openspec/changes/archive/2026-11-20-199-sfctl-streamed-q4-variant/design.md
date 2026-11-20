# Design

## Decisions

### D1. Per-variant arguments

`load_conf` unsets and reads `SF_ARGS_<cv>` for each listed variant, applies
the same character checks as `SF_ARGS`, and the agent's argument list is
`SF_ARGS` followed by the variant's. `@VARIANT@` and `@HOME@` expand in
both. `plist` prints the result, so the owner can read what `start` would
run before anything changes. A test in `tests/test_sfctl.sh`: a config
with and without `SF_ARGS_<variant>`, the generated plist, and rejection of
forbidden characters.

### D2. The variant's arguments

`SF_MODEL_q4s=q4:gguf/Qwen3.8-Flash-Next-Q4.gguf` (the same component and
weights as `q4`) and `SF_ARGS_q4s='--ssd-streaming
--ssd-streaming-cache-experts 9701'`. The disk KV of `q4` is valid for the
same weights, but a separate directory keeps the two variants' space limits
apart; `@VARIANT@` already gives `kv-q4s`.

### D3. The service-level check

A temporary serve worktree of the branch under the scratch directory,
started on a free port with the generated arguments by hand (not through
the owner's launchd label), one model process at a time under the memory
guard. A scripted agent session through `/v1/chat/completions`:
a 20K-token system prompt, ten turns each with a 1-4K tool result and a
200-token answer. Figures: time to first token per turn, decode rate,
`footprint` once a second. The same session against resident `q4` for
reference.

### D4. Mirroring

Checked in each child before landing: its `sfctl/sf-<model>.conf` is
unchanged, `sfctl plist <service>` prints the same arguments as before the
change, and `grep -n ssd sfctl/sfctl sfctl/README.md tests/test_sfctl.sh`
finds nothing.


The other children with `sfctl` get the identical `sfctl/sfctl`,
`sfctl/README.md` and `tests/test_sfctl.sh` on a branch each, with their
own `make test`; no other file changes there. Landing in each child follows
that child's rules; if one of them cannot land tonight, this child keeps
the change on its branch until they can.

## Risks / Trade-offs

- A shared script changed in one child and not the others breaks the rule
  that they are identical; D4 keeps them in step.
