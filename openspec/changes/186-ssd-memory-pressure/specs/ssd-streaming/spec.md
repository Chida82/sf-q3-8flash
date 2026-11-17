## ADDED Requirements

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
