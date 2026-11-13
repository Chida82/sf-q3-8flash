# Spec Delta

## Purpose

Defines how a StarForge child's model is installed, run, stopped, inspected, synced to main and removed as an on-demand local launchd service through `sfctl`, from a build that always matches one commit of main.

## ADDED Requirements

### Requirement: No service starts on its own
An installed service SHALL start only through `sfctl start <model>`. It SHALL NOT start at login, at install, or after it exits.

#### Scenario: Login
- **WHEN** the owner logs in with `q3-8flash` installed
- **THEN** no `sf-q3-8flash-server` process is running

#### Scenario: Service exits
- **WHEN** a running service exits or crashes
- **THEN** it stays stopped until the next `sfctl start q3-8flash`

### Requirement: Commands name their model
Every command that acts on one model (`start`, `stop`, `restart`, `update`, `uninstall`, `logs`, `follow`, `plist`) SHALL require the model name and SHALL fail with a usage error without it. A model that is not installed SHALL be reported by name.

#### Scenario: Stop without a model
- **WHEN** the owner runs `sfctl stop` while `q3-8flash` is running
- **THEN** sfctl exits with an error that names the running model and stops nothing

#### Scenario: Unknown model
- **WHEN** the owner runs `sfctl start no-such-model` and that model is not installed
- **THEN** sfctl exits with an error saying `no-such-model` is not installed

### Requirement: Status covers every installed model
`sfctl status` without a model SHALL list every installed model, each with its state (running with pid, or stopped), its port, the serve commit, and whether that commit differs from local `main`.

#### Scenario: Serve behind main
- **WHEN** a change was merged into `main` and serve was not updated
- **THEN** `sfctl status` marks `q3-8flash` as behind main and shows both commits

### Requirement: One engine at a time
`sfctl start` SHALL refuse while another sfctl service is running, or while any ds4 engine instance lock (`/tmp/ds4.lock` or `/tmp/sf-*.lock`) is held by a process. The message SHALL name the holder's pid and, for an sfctl service, the command that stops it.

#### Scenario: Another model is running
- **WHEN** `ds4-1flash` runs as an sfctl service and the owner runs `sfctl start q3-8flash`
- **THEN** sfctl refuses, naming `ds4-1flash`, its pid and `sfctl stop ds4-1flash`

#### Scenario: A manual engine run holds a lock
- **WHEN** a manually started `sf-q3-8flash` CLI, or an upstream ds4 server, holds its instance lock
- **THEN** `sfctl start q3-8flash` refuses and names that pid

### Requirement: The service runs from a serve worktree at main
`sfctl install` SHALL create a git worktree of the child at `~/.sf/<model>/serve`, detached at local `main`, build it, and run the service from it. The service SHALL NOT run binaries or read Metal sources or steering profiles from any other checkout.

#### Scenario: Development branch checked out
- **WHEN** the development checkout is on a work branch with edited kernels and the owner restarts the service
- **THEN** the service runs the binary and kernels of serve's commit

### Requirement: Update syncs serve to local main
`sfctl update <model>` SHALL bring serve to local `main` and rebuild it. A running service SHALL be stopped first and started again after a successful build; a stopped service SHALL stay stopped. It SHALL refuse when serve has local modifications, and SHALL report the old and new commit.

#### Scenario: Update while running
- **WHEN** `q3-8flash` is running and the owner runs `sfctl update q3-8flash` after a merge
- **THEN** the service stops, serve moves to `main`, the build completes, the service starts again, and sfctl prints the old and new commit

#### Scenario: Dirty serve
- **WHEN** a file in serve was modified
- **THEN** `sfctl update` refuses without stopping the service and names the modified path

#### Scenario: Failed build
- **WHEN** the build fails after serve moved to the new commit
- **THEN** sfctl exits with an error and the service is not started

### Requirement: The sfctl files are shared unchanged
`sfctl/sfctl`, `sfctl/README.md` and `tests/test_sfctl.sh` SHALL be byte-identical in every child that has them, and SHALL NOT name a model. Everything specific to a model SHALL be in its `sfctl/sf-<model>.conf`, whose top comment describes the service it runs. The test SHALL read the model, server and port from the checkout's only config.

#### Scenario: Compare with a sibling
- **WHEN** the three shared files are compared with `sf-ds4-1flash`'s
- **THEN** `cmp` finds them identical

#### Scenario: Test reads the config
- **WHEN** `make test` runs in this child
- **THEN** the sfctl checks name port 8912 and `sf-q3-8flash-server` inside serve

### Requirement: This model's service changes no output
The service options SHALL NOT change model output: built-in MTP SHALL run with `--mtp-exact-sampling`, and no option SHALL quantize the KV cache or activations.

#### Scenario: Sampled request
- **WHEN** a request with nonzero temperature reaches the service
- **THEN** tokens are sampled from the ordinary distribution, as without `--mtp`

### Requirement: Install links models under any hf output form
`sfctl install` SHALL link the configured GGUF components whether `hf download` prints the bare cached path or hints followed by `path=<file>`.

#### Scenario: Agent-run install
- **WHEN** an AI agent runs `sfctl/sfctl install` and `hf` prints `path=<file>`
- **THEN** `download.sh` links the cached file and the install completes

### Requirement: Model config is per model and generic
Each model SHALL have one config file in its child's repository that sets the service port, the server binary, the GGUF components to link, and the server options. Neither that file, nor the script, nor its README SHALL contain a user name, a home path or a machine-specific path. Those come from the environment at install time.

#### Scenario: Repository files
- **WHEN** the files under `sfctl/` are searched for `/Users/`
- **THEN** there is no match

#### Scenario: Different binaries
- **WHEN** two children are installed
- **THEN** each agent runs its own child's server binary with its own options, from its own serve worktree

### Requirement: Boost needs are checked before start
When a model's server options ask for boost (an option starting with `--boost`), `sfctl start` SHALL run `fanboost check` first and SHALL refuse to start with a message pointing to `fanboost/install.sh` when the check fails. A model whose options do not ask for boost SHALL start without fanboost.

#### Scenario: No boost in this model's options
- **WHEN** the owner runs `sfctl start q3-8flash` on a Mac without fanboost
- **THEN** sfctl starts the service without running `fanboost check`

### Requirement: Uninstall keeps data
`sfctl uninstall <model>` SHALL stop the service, remove its launchd agent and its serve worktree, and SHALL keep the disk KV cache, the logs, the CLI history and the Hugging Face model cache. It SHALL remove the `sfctl` command link only when that link points into the removed worktree.

#### Scenario: Uninstall
- **WHEN** the owner runs `sfctl uninstall q3-8flash`
- **THEN** `~/.sf/q3-8flash/serve` and the agent are gone, and `~/.sf/q3-8flash/kv` and the GGUF files in the Hugging Face cache are still there

### Requirement: The agent definition can be inspected
`sfctl plist <model>` SHALL print the launchd agent definition that `install` and `update` write, without changing anything.

#### Scenario: Inspect
- **WHEN** the owner runs `sfctl plist q3-8flash`
- **THEN** a valid property list is printed, its program is `sf-q3-8flash-server` inside serve, and no file is written
