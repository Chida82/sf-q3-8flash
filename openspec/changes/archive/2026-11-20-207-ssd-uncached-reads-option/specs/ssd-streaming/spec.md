## ADDED Requirements

### Requirement: Uncached expert reads at launch
With `--ssd-streaming`, the option `--ssd-streaming-uncached` SHALL make the
engine read routed experts past the file cache. The default SHALL stay
buffered. Greedy output SHALL be token-identical in both modes. The option
SHALL be accepted by the CLI, the server, the bench and the eval tool, and
the environment variable `DS4_METAL_STREAM_EXPERT_UNCACHED_READS=1` SHALL
keep the same effect.

#### Scenario: Option given with streaming
- **WHEN** the engine opens with `--ssd-streaming --ssd-streaming-uncached`
- **THEN** it logs that SSD expert reads bypass the file cache, and a run leaves only the static weights of the GGUF in the file cache

#### Scenario: Option without streaming
- **WHEN** `--ssd-streaming-uncached` is given without `--ssd-streaming`
- **THEN** the engine refuses to open and names the missing option

#### Scenario: Uncached descriptor unavailable
- **WHEN** the second descriptor cannot be opened or configured
- **THEN** the engine says so and reads stay buffered
