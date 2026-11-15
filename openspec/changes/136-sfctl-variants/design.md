# Design

## Context

`sfctl` runs one launchd agent per model from a serve worktree. The agent is
written at `install` and `update` from `sfctl/sf-<model>.conf` and loaded at
`start`. The same script, README and test ship in every child.

## Decisions

### D1. One service, variants by name

A variant is not a second service: one serve, one label, one port, one home,
one build. Its name is `<model>-<variant>`. Model names contain `-`
(`q3-8flash`), so resolution tries the whole name as a model first, then
splits at the last `-` and requires the suffix in that model's
`SF_VARIANTS`; variant names are letters, digits and `_`. An unknown suffix is
refused with the model's service names.

### D2. Config shape

```sh
SF_VARIANTS="q4 q2"
SF_MODEL_q4=q4:gguf/Qwen3.8-Flash-Next-Q4.gguf
SF_MODEL_q2=q2:gguf/Qwen3.8-Flash-Next-Q2.gguf
SF_ARGS='... --kv-disk-dir @HOME@/kv-@VARIANT@ ...'
```

`SF_MODEL_<variant>` uses the `component:path` form of `SF_COMPONENTS`: the
path goes to `-m`, the component to `./download.sh`. Every other server
option is shared; the two variants keep the same context, MTP, vision and KV
budget.

### D3. The agent is written at start

The agent carries the variant's `-m` and KV dir, so `start <model>-<variant>`
unloads a loaded agent, writes the variant's (`plutil -lint` as before), and
loads it. `install` and `update` still write one, so that an installed model
has its agent file: for the recorded variant, else the first listed. The first
variant is also what an agent written before variants ran (Q4 here), so an
`update` that restarts such a service keeps its weights.

### D4. The variant is recorded in `~/.sf/<model>/variant`

`start` writes the name there before loading. `status` reads it: `running q2
pid N`, or `stopped (last q2)`. It is only shown for a config with variants,
and nothing is claimed when no record exists. `restart <model>` restarts the
recorded variant.

### D5. Fixed model links, linked by install and update only

The service never reads the root default link. `install` and `update` link
each missing variant model through `./download.sh <component>`, the child's
only sanctioned linker; its side effect of re-pointing the default link is
harmless. `start` never links or downloads: a missing model fails with
`sfctl update <model>`. `restart` checks this before stopping anything.

### D6. KV per variant; the old dir is left alone

Q4 and Q2 checkpoints are not interchangeable and would evict each other in
one budget, so `@VARIANT@` names a dir per variant: `kv-q4`, `kv-q2`. The
pre-variant `~/.sf/q3-8flash/kv` is not moved or deleted; the owner may
delete it, or rename it to `kv-q4` while the service is stopped to keep the
warm Q4 cache. `write_plist` no longer pre-creates `@HOME@/kv`: the server
creates its KV dir (`kv_mkdir_p`).

### D7. Tests without the machine

`tests/test_sfctl.sh` already points `HOME` at a scratch dir, so
`~/Library/LaunchAgents`, logs and `~/.sf` are scratch too. Fixture configs in
fake serve dirs cover a model without variants (its agent compared with a
literal copy of the pre-variant output) and one with variants. Stub
`launchctl`, `lsof` and `make` on `PATH` let `start`, `status` and `update`
run end to end without touching launchd or building. The update fixture is a
git serve one commit behind `main`, whose `main` script logs its own runs: the
test sees `_update-finish` arrive there.

### D8. update hands over to the script it checks out

`update` runs serve's script, which `git checkout` replaces while it runs; the
shell keeps executing the old code, so a format change in `main` (variants
here) would be written by a script that does not know it. After the checkout,
`update` therefore `exec`s serve's new `sfctl/sfctl _update-finish <model>
<old> <was>`, which builds, links, writes the agent and restarts with its own
logic. `_update-finish` is internal (not in usage); its name and arguments
stay stable because the previous script calls it.

Run from another checkout, `update` acts on serve the same way: every path it
touches comes from `serve_dir`, the config is read from serve, and the
handover runs serve's script. `SFDIR` only matters for `install` and for
`plist` of a model that is not installed. Serve's current script predates the
handover, so the first update after this change runs from the main checkout
(tasks 4.1).

## Risks

- `update` on a machine where the Q2 GGUF is not in the Hugging Face cache
  downloads it (137 GiB). Here both are cached; the first `update` only links
  and verifies Q2's SHA-256.
