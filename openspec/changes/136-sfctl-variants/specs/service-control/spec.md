# Spec Delta

## MODIFIED Requirements

### Requirement: No service starts on its own
An installed service SHALL start only through `sfctl start <service>`. It SHALL NOT start at login, at install, or after it exits.

#### Scenario: Login
- **WHEN** the owner logs in with `q3-8flash` installed
- **THEN** no `sf-q3-8flash-server` process is running

#### Scenario: Service exits
- **WHEN** a running service exits or crashes
- **THEN** it stays stopped until the next `sfctl start q3-8flash-q4` or `sfctl start q3-8flash-q2`

### Requirement: Commands name their model
Every command that acts on one model (`start`, `stop`, `restart`, `update`, `uninstall`, `logs`, `follow`, `plist`) SHALL require a service name and SHALL fail with a usage error without it. A service name SHALL be `<model>`, or `<model>-<variant>` for a model whose config lists variants; both SHALL act on the model's one service. A model that is not installed SHALL be reported by name.

#### Scenario: Stop without a model
- **WHEN** the owner runs `sfctl stop` while `q3-8flash` is running
- **THEN** sfctl exits with an error that names the running model and stops nothing

#### Scenario: Unknown model
- **WHEN** the owner runs `sfctl start no-such-model` and that model is not installed
- **THEN** sfctl exits with an error saying `no-such-model` is not installed

#### Scenario: Variant name on another command
- **WHEN** the owner runs `sfctl stop q3-8flash-q2` while `q3-8flash` runs Q4
- **THEN** sfctl stops the `q3-8flash` service

### Requirement: Status covers every installed model
`sfctl status` without a model SHALL list every installed model, each with its state (running with pid, or stopped), its port, the serve commit, and whether that commit differs from local `main`. For a model with variants it SHALL show the running variant, or for a stopped service the variant last started when one is recorded.

#### Scenario: Serve behind main
- **WHEN** a change was merged into `main` and serve was not updated
- **THEN** `sfctl status` marks `q3-8flash` as behind main and shows both commits

#### Scenario: Running variant
- **WHEN** the owner started `q3-8flash-q2`
- **THEN** `sfctl status` shows `q3-8flash running q2` with its pid, and `stopped (last q2)` after it stops

### Requirement: One engine at a time
`sfctl start` SHALL refuse while another sfctl service is running, or while any ds4 engine instance lock (`/tmp/ds4.lock` or `/tmp/sf-*.lock`) is held by a process. The message SHALL name the holder's pid and, for an sfctl service, the command that stops it.

#### Scenario: Another model is running
- **WHEN** `ds4-1flash` runs as an sfctl service and the owner runs `sfctl start q3-8flash-q4`
- **THEN** sfctl refuses, naming `ds4-1flash`, its pid and `sfctl stop ds4-1flash`

#### Scenario: A manual engine run holds a lock
- **WHEN** a manually started `sf-q3-8flash` CLI, or an upstream ds4 server, holds its instance lock
- **THEN** `sfctl start q3-8flash-q4` refuses and names that pid

### Requirement: Update syncs serve to local main
`sfctl update <service>` SHALL bring serve to local `main` and rebuild it. A running service SHALL be stopped first and started again, on the same variant, after a successful build; a stopped service SHALL stay stopped. It SHALL refuse when serve has local modifications, and SHALL report the old and new commit. After moving serve, it SHALL hand over to the `sfctl` script serve now holds, which builds, links the models, writes the agent and restarts the service with its own logic. Run from a checkout other than serve, `update` SHALL act on serve in the same way.

#### Scenario: Update while running
- **WHEN** `q3-8flash` is running and the owner runs `sfctl update q3-8flash` after a merge
- **THEN** the service stops, serve moves to `main`, the build completes, the service starts again, and sfctl prints the old and new commit

#### Scenario: Dirty serve
- **WHEN** a file in serve was modified
- **THEN** `sfctl update` refuses without stopping the service and names the modified path

#### Scenario: Failed build
- **WHEN** the build fails after serve moved to the new commit
- **THEN** sfctl exits with an error and the service is not started

#### Scenario: Main changed the agent format
- **WHEN** `main` changes how the agent is written and the owner runs `sfctl update q3-8flash` with serve's older script
- **THEN** the agent is written by `main`'s script

### Requirement: Boost needs are checked before start
When a model's server options ask for boost (an option starting with `--boost`), `sfctl start` SHALL run `fanboost check` first and SHALL refuse to start with a message pointing to `fanboost/install.sh` when the check fails. A model whose options do not ask for boost SHALL start without fanboost.

#### Scenario: No boost in this model's options
- **WHEN** the owner runs `sfctl start q3-8flash-q4` on a Mac without fanboost
- **THEN** sfctl starts the service without running `fanboost check`

### Requirement: Uninstall keeps data
`sfctl uninstall <service>` SHALL stop the service, remove its launchd agent and its serve worktree, and SHALL keep the disk KV caches, the logs, the CLI history and the Hugging Face model cache. It SHALL remove the `sfctl` command link only when that link points into the removed worktree.

#### Scenario: Uninstall
- **WHEN** the owner runs `sfctl uninstall q3-8flash`
- **THEN** `~/.sf/q3-8flash/serve` and the agent are gone, and `~/.sf/q3-8flash/kv-q4`, `~/.sf/q3-8flash/kv-q2` and the GGUF files in the Hugging Face cache are still there

### Requirement: The agent definition can be inspected
`sfctl plist <service>` SHALL print the launchd agent definition that sfctl writes for that service, without changing anything: for `<model>-<variant>` that variant's, for a model with variants named alone the variant last started, else the first listed.

#### Scenario: Inspect
- **WHEN** the owner runs `sfctl plist q3-8flash`
- **THEN** a valid property list is printed, its program is `sf-q3-8flash-server` inside serve, and no file is written

#### Scenario: Inspect a variant
- **WHEN** the owner runs `sfctl plist q3-8flash-q2`
- **THEN** the printed agent passes `-m gguf/Qwen3.8-Flash-Next-Q2.gguf` and the KV dir `~/.sf/q3-8flash/kv-q2`

## ADDED Requirements

### Requirement: Variants select the weights
A model config MAY list variants in `SF_VARIANTS`, each with its model in `SF_MODEL_<variant>`. The model SHALL keep one service: one serve worktree, one launchd label, one port, one home. `start` SHALL write the named variant's agent before loading it and SHALL record the variant under `~/.sf/<model>/`.

#### Scenario: One service
- **WHEN** the owner starts `q3-8flash-q2` after running `q3-8flash-q4`
- **THEN** both ran under the label `com.starforge.sf-q3-8flash`, on port 8912, from `~/.sf/q3-8flash/serve`

### Requirement: Start needs a known variant
For a model with variants, `sfctl start` SHALL require `<model>-<variant>`, SHALL refuse `<model>` alone with a usage error listing the variant names, and SHALL refuse an unknown variant.

#### Scenario: Start without a variant
- **WHEN** the owner runs `sfctl start q3-8flash`
- **THEN** sfctl exits with a usage error listing `q3-8flash-q4` and `q3-8flash-q2`

#### Scenario: Unknown variant
- **WHEN** the owner runs `sfctl start q3-8flash-q3`
- **THEN** sfctl refuses and lists `q3-8flash-q4` and `q3-8flash-q2`

### Requirement: Variants switch through restart
While one variant runs, `start` of another SHALL be refused with the running variant and the `restart` command to run. `restart <model>-<variant>` SHALL stop the service and start that variant.

#### Scenario: Another variant is running
- **WHEN** `q3-8flash-q2` runs and the owner runs `sfctl start q3-8flash-q4`
- **THEN** sfctl refuses, naming `q3-8flash-q2` and `sfctl restart q3-8flash-q4`

#### Scenario: Switch
- **WHEN** `q3-8flash-q2` runs and the owner runs `sfctl restart q3-8flash-q4`
- **THEN** the service stops and starts again on Q4

### Requirement: Each variant passes its own model
Each variant's agent SHALL pass its model's fixed path with `-m` (`gguf/Qwen3.8-Flash-Next-Q4.gguf`, `gguf/Qwen3.8-Flash-Next-Q2.gguf`), and SHALL NOT depend on the root default link `qwen3.8-flash-next.gguf`.

#### Scenario: Default link re-pointed
- **WHEN** `./download.sh q2` re-points serve's default link to Q2 and the owner starts `q3-8flash-q4`
- **THEN** the service loads Q4

### Requirement: Each variant has its own disk KV cache
Each variant SHALL use its own disk KV directory, `~/.sf/<model>/kv-<variant>` through `@VARIANT@` in the server options. sfctl SHALL NOT move or delete an existing KV directory.

#### Scenario: Old cache dir
- **WHEN** the owner updates to variants with `~/.sf/q3-8flash/kv` present
- **THEN** that directory and its files are left unchanged, and Q4 uses `~/.sf/q3-8flash/kv-q4`

### Requirement: Start never links or downloads
`sfctl install` and `sfctl update` SHALL link every variant's model that serve lacks, through `./download.sh`. `sfctl start` and `sfctl restart` SHALL NOT link or download anything: when the variant's model is missing in serve they SHALL fail, before stopping anything, with a message naming the missing path and `sfctl update <model>`.

#### Scenario: Missing model at start
- **WHEN** serve has no `gguf/Qwen3.8-Flash-Next-Q2.gguf` and the owner runs `sfctl start q3-8flash-q2`
- **THEN** sfctl refuses, names that path and `sfctl update q3-8flash`, and nothing is downloaded

### Requirement: A config without variants keeps its agent
For a config without `SF_VARIANTS`, the agent sfctl writes SHALL be byte-identical to the one written before variants existed.

#### Scenario: Fixture config
- **WHEN** the sfctl test prints the agent of a fixture config without variants
- **THEN** it equals the recorded pre-variant agent
