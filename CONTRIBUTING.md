# Contributing

Read `AGENTS.md` and `AGENT.md` before editing. Work on a topic branch, keep
changes Qwen3.8/Metal-specific, and do not rename `ds4_*` files or identifiers.

Run `make -j8 && make test -j8`. Add one focused regression for non-trivial new
logic and run the relevant Qwen model-backed tests when a local GGUF is
available. Performance changes require token-identical parity and comparable
median measurements.

Do not commit or push changes prepared by an automated agent unless the user
explicitly requests it. Preserve `LICENSE` and upstream attribution.
