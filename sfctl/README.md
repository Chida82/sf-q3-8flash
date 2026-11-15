# sfctl

`sfctl` runs a StarForge model as an on-demand local service on macOS, through
a launchd agent in the user's session. It is written for agents: follow the
procedures below as written.

- One script, the same in every child (`sfctl/sfctl`, with this README and
  `tests/test_sfctl.sh`), and one config per model (`sfctl/sf-<model>.conf`).
  `<model>` is the child's name without `sf-`. The comments at the top of the
  config describe the service it runs.
- Each service runs from its own **serve worktree**, `~/.sf/<model>/serve`: a git
  worktree of the child detached at local `main`, built there. Binary, Metal
  sources and steering profiles therefore always come from one commit of `main`,
  never from a development branch.
- Nothing starts at login, and nothing restarts after an exit or a crash. A
  model runs only after `sfctl start <model>`.
- One engine at a time: `start` refuses while another sfctl service runs, or
  while any process holds an engine instance lock (`/tmp/ds4.lock`,
  `/tmp/sf-*.lock`), which covers manual runs and upstream ds4.
- A model may have **variants**, one set of weights each (see Variants). It is
  still one service: one serve, one agent, one port, one home.

## Ask the owner before `install` or `uninstall`

Both change the machine: a worktree under `~/.sf/`, a LaunchAgent plist, logs
under `~/Library/Logs/sf/`, and the `~/.local/bin/sfctl` link. Run them only
after the owner has said yes for this machine. `start`, `stop` and `update` load
or unload a model of tens to hundreds of GiB from SSD: do not run them while the machine is
measuring something (a benchmark, an A/B run, an eval).

## Prerequisites

- macOS on Apple silicon, with the child's own build prerequisites (`make`, the
  Xcode command line tools).
- The Hugging Face CLI, `hf`, for `./download.sh`. Models live once in the shared
  Hugging Face cache; serve only holds links to them.
- `~/.local/bin` on `PATH`, for the `sfctl` command.
- fanboost, when the model's config asks for boost (an `SF_ARGS` option that
  starts with `--boost`): `./fanboost/install.sh` in the child, see
  `fanboost/README.md`. `start` runs `fanboost check` and refuses when it fails.

## Install

From a checkout of the child (any worktree), after the change that added the
model's `.conf` is merged into `main`:

```sh
./sfctl/sfctl install            # the checkout's only model; or: install <model>
```

It:
1. refuses if `~/.sf/<model>/serve` already exists (use `update`) or `main` has
   no `sfctl/sf-<model>.conf`;
2. creates the serve worktree at `main` and builds the server there;
3. runs `./download.sh <component>` in serve for each model link it lacks,
   every variant's model included (the first time this verifies or downloads
   the GGUFs through `hf`);
4. writes the agent `~/Library/LaunchAgents/com.starforge.sf-<model>.plist`
   (for a model with variants, the first variant's), without loading it;
5. creates `~/.local/bin/sfctl` pointing to serve's script, only when that
   path is free or already a link into some `~/.sf/*/serve`.

Verify:
- `sfctl status` shows `<model> stopped port <port>, serve <sha> = main`;
- `plutil -lint ~/Library/LaunchAgents/com.starforge.sf-<model>.plist` passes;
- `launchctl print gui/$(id -u)/com.starforge.sf-<model>` fails: nothing is
  loaded until `start`.

## Commands

```text
sfctl install [<model>]     from a child checkout (see Install)
sfctl update <service>      sync serve to local main and rebuild (see Syncing serve)
sfctl start <service>       start the service; with variants, <model>-<variant>
sfctl stop <service>        stop the service
sfctl restart <service>     stop, then start; <model>-<variant> switches variant
sfctl status [<service>]    state, variant, pid, port and serve commit; all models without a name
sfctl logs <service> [N]    last N lines of the service log (default 80)
sfctl follow <service>      follow the service log
sfctl plist <service>       print the launchd agent definition, write nothing
sfctl uninstall <service>   remove the agent and serve; keep KV, logs and models
```

`<service>` is `<model>`, or `<model>-<variant>` for a model with variants.
Every command except `install` and `status` needs it; without it sfctl exits
with a usage error that names the running model, if any.

A session, with `<port>` the config's `SF_PORT`:

```sh
sfctl start <model>             # returns at once; the model loads in the background
sfctl follow <model>            # until "listening on http://127.0.0.1:<port>"
curl -s 127.0.0.1:<port>/v1/models
sfctl status
sfctl logs <model> 200
sfctl stop <model>
```

Logs go to `~/Library/Logs/sf/<model>.out.log` and `.err.log`. The service
itself (model files, context, cache, speculation, steering, boost) is described
in the comments at the top of `sfctl/sf-<model>.conf`.

## Variants

A config with `SF_VARIANTS="q4 q2"` and one `SF_MODEL_<variant>=component:path`
per variant runs the same service on different weights. The service name
`<model>-<variant>` picks them:

```sh
sfctl start <model>-q4          # a model with variants needs the variant
sfctl status                    # <model> running q4 pid ... port ...
sfctl restart <model>-q2        # stop, then start q2
sfctl stop <model>              # any command but start takes either name
```

- `start <model>` is a usage error listing the variants. `start` of another
  variant while one runs is refused and suggests `restart <model>-<variant>`.
  `restart <model>` restarts the variant last started.
- `start` writes the variant's agent (`plutil -lint` checked), reloads it, and
  records the variant in `~/.sf/<model>/variant`; `status` reads it, and shows
  `stopped (last <variant>)` for a stopped service. `update` keeps the recorded
  variant; with none recorded it uses the first listed, which is what an agent
  written before variants ran.
- The agent passes `-m <path>` from `SF_MODEL_<variant>`, so a variant never
  depends on a default model link that `./download.sh` may re-point.
- `@VARIANT@` in `SF_ARGS` becomes the variant's name, for example
  `--kv-disk-dir @HOME@/kv-@VARIANT@`: weights of different quantization need
  separate disk KV caches. sfctl never moves or deletes an older cache dir.
- `install` and `update` link every variant's model that serve lacks, through
  `./download.sh <component>`. `start` never links or downloads: when the
  variant's model is missing it fails and says to run `sfctl update <model>`.
- `plist <model>-<variant>` prints that variant's agent; `plist <model>` the
  recorded variant's, else the first's.

## Syncing serve

A request to "sync sfctl" or "sync serve" means this procedure. Serve follows
the child's local `main`; it is never updated from a work branch.

Preconditions:
1. The change is merged into the child's local `main`. A change still on a work
   branch is not served.
2. Serve is clean: `git -C ~/.sf/<model>/serve status --porcelain` prints
   nothing. Serve is never edited by hand; if it is dirty, stop and report the
   paths to the owner instead of discarding them.
3. The machine is not measuring anything.

Run:

```sh
sfctl status                 # note the state and the serve commit
sfctl update <model>
```

`update` refuses on a dirty serve without stopping anything. Otherwise it stops
the service if it is running, moves serve to `main`, and hands over to the
`sfctl` that `main` just put in serve, so the rest always runs with `main`'s
logic, however old the script that started the update. That script builds the
server, links
any model the config needs and serve lacks (every variant's included; this can
download tens of GiB when a model is not in the Hugging Face cache yet),
rewrites the agent (for the recorded variant), starts the service again only if
it was running, and prints `old..new` with the commits in between. If the build
fails it stops there and leaves the service stopped.

Verify:
- `sfctl status` shows `serve <sha> = main` (and the variant, for a model with
  variants that has been started);
- if the service was running: it is running again, and `sfctl logs <model>`
  shows a new start (`listening on ...`) after the update.

Report to the owner the `old..new` range and its commits
(`git -C ~/.sf/<model>/serve log --oneline old..new`), and whether the service
was restarted.

## Uninstall

```sh
sfctl uninstall <model>
```

It stops the service, removes the agent and the serve worktree, and removes
`~/.local/bin/sfctl` only when it points into that worktree (then it relinks it
to another installed model, if any). It keeps `~/.sf/<model>` (KV caches, CLI
history, the recorded variant), the logs and the Hugging Face cache. A serve with local modifications
is not removed: git refuses and sfctl reports it.

## Adding a model

A child adds its own service in its own change:
1. copy `sfctl/sfctl`, this README and `tests/test_sfctl.sh` from a child that
   has them, unchanged;
2. write `sfctl/sf-<model>.conf` with `SF_PORT` (one per child: 8909 ds4flash,
   8910 ds4-1flash, 8911 glm5-3flash, 8912 q3-8flash), `SF_SERVER`,
   `SF_COMPONENTS` (`component:path` pairs for `./download.sh`) and `SF_ARGS`
   (server options after `--port`; relative paths resolve in serve; `@HOME@`
   becomes `~/.sf/<model>`; no option may contain a space), with a comment
   block at the top describing the service. For several weights add
   `SF_VARIANTS` (names of letters, digits and `_`) and one
   `SF_MODEL_<variant>=component:path` each, passed as `-m` before `SF_ARGS`;
   `@VARIANT@` in `SF_ARGS` becomes the variant's name. A config without
   `SF_VARIANTS` writes the same agent as before variants existed;
3. add `sh tests/test_sfctl.sh` to `make test`; it reads the model, server and
   port from the config.

Nothing in `sfctl/` may name a user or a machine path: everything specific to a
machine is computed when sfctl runs.
