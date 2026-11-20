# ssd-streaming Specification

## Purpose

Lets Qwen3.8 Flash Next run on Macs whose RAM cannot hold all routed experts,
by reading routed experts from the GGUF into a bounded GPU cache, with output
identical to a resident run.

## Requirements

### Requirement: Streamed routed experts
With `--ssd-streaming` on Metal, the engine SHALL keep dense, shared, HC,
router, head and embedding weights mapped as today and SHALL read routed
experts on demand into a bounded cache of owned GPU buffers. The routed-expert
kernels SHALL take the experts' addresses from the cache while keeping their
arithmetic, so greedy output SHALL be token-identical to the resident run of
the same build, for prefill, decode and built-in MTP, on both the Q4 and Q2
packs.

#### Scenario: Identical output
- **WHEN** the same prompt runs greedy with and without `--ssd-streaming`
- **THEN** the generated token ids are identical

#### Scenario: Cache smaller than a batch
- **WHEN** a prefill batch needs more distinct experts than the cache holds
- **THEN** the batch completes through layer staging and the output is still identical

### Requirement: Resident path unchanged
Without `--ssd-streaming`, the routed kernels SHALL run with the address path
compiled out, and output SHALL be bitwise identical to the build before
streaming was added.

#### Scenario: Resident logits
- **WHEN** a resident run of this build and of the previous `main` dump frontier logits
- **THEN** every logit has the same bits

### Requirement: Engine-open admission
The Qwen refusal at engine open SHALL no longer reject `--ssd-streaming`; it
SHALL still reject tensor parallelism, pipeline execution and power
throttling. Before loading, the engine SHALL plan the memory for static
weights, context, prefill chunk, staging and the expert cache from the
smaller of 87.5% of physical RAM and Metal's recommended working set. When
the fixed part leaves no room for a cache, it SHALL refuse with a message
naming the needed and the available GiB and suggesting a smaller context or
prefill chunk.

#### Scenario: Too little memory
- **WHEN** the fixed requirements exceed the budget
- **THEN** the engine refuses to open and names both figures

#### Scenario: Other modes still refused
- **WHEN** Qwen opens with `--ssd-streaming` and a tensor-parallel role
- **THEN** the engine refuses as before

### Requirement: Documented memory policy
The documentation SHALL describe how to enable streaming, how the cache is
sized, the minimum RAM measured for each pack, and the throughput measured at
emulated 48 GB and 40 GB machines, and states the emulation's limits.

#### Scenario: Minimum RAM
- **WHEN** a reader looks up whether a 32 GB Mac runs the Q4 pack
- **THEN** `docs/SSD_STREAMING.md` states the measured minimum and the expected decode rate

### Requirement: Expert cache follows memory pressure
With `--ssd-streaming`, the engine SHALL observe the system memory-pressure
level. On a warning it SHALL release part of the expert cache, and on a
critical level it SHALL release the cache down to a floor that still lets the
request in flight complete. After a quiet period it SHALL regrow the cache
step by step, never beyond the size planned at engine open. Greedy output
SHALL stay token-identical to the resident run whatever the cache size.

#### Scenario: Warning during decode
- **WHEN** a memory-pressure warning arrives while a streamed request decodes
- **THEN** the expert cache shrinks at the next layer boundary, the engine logs the old and new sizes, and the generated token ids are identical to a resident run

#### Scenario: Critical level
- **WHEN** the level is critical
- **THEN** the cache shrinks to its floor and the request in flight completes

#### Scenario: Regrowth
- **WHEN** no warning or critical level has been seen for the quiet period
- **THEN** the cache grows by one step, and repeats until it reaches the planned size

#### Scenario: Pressure at open
- **WHEN** the level is not normal at engine open
- **THEN** the engine opens with the cache at its floor and says so

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
