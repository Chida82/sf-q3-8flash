# Tasks

## 1. sfctl

- [x] 1.1 Resolve `<model>` and `<model>-<variant>`; refuse unknown variants.
- [x] 1.2 `SF_VARIANTS`, `SF_MODEL_<variant>` and `@VARIANT@` in `load_conf` and the agent; `-m` per variant.
- [x] 1.3 `start` requires a variant, refuses another running variant, writes the agent and records the variant; `restart` switches.
- [x] 1.4 `status` shows the running or last variant; `install`/`update` link every variant's model; `start` links nothing.
- [x] 1.5 `update` hands over to the script it checked out (`_update-finish`) for build, links, agent and restart.

## 2. Config and docs

- [x] 2.1 `sf-q3-8flash.conf`: `q4` and `q2` on the fixed links, KV per variant.
- [x] 2.2 `sfctl/README.md`, `AGENTS.md`, `README.md`.

## 3. Tests

- [x] 3.1 `tests/test_sfctl.sh`: resolution, `start <model>` refused, per-variant agents, unchanged agent without variants, unknown variant, start/status/update through stubs.
- [x] 3.3 Spec delta for `service-control`; `openspec validate 136-sfctl-variants --strict`.
- [x] 3.2 `sh -n sfctl/sfctl`, the suite under sh and dash, `make test -j8`.

## 4. Serve (owner)

- [x] 4.1 After the merge into `main`, from the child's main checkout (serve's own script is pre-136 and does not hand over): `./sfctl/sfctl update q3-8flash`. It links Q2, writes the Q4 agent, and restarts the service on Q4 if it was running. Then `sfctl status`, and `sfctl start q3-8flash-q4` if it was stopped. Later updates run as `sfctl update q3-8flash`.
