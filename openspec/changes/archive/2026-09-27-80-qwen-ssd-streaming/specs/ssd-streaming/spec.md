# ssd-streaming Specification

## Purpose

Lets Qwen3.8 Flash Next run on Macs whose RAM cannot hold all routed experts,
by reading routed experts from the GGUF into a bounded GPU cache, with output
identical to a resident run.

## ADDED Requirements

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
