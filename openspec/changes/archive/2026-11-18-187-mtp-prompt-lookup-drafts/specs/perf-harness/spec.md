## MODIFIED Requirements

### Requirement: Metric set
The harness SHALL measure these run kinds, each selectable:
- **plain**: prefill tok/s for 8192 new tokens from an empty context, then 512
  and 2048 new tokens resumed on top of it; plain greedy decode tok/s;
- **MTP, code prompt** and **MTP, prose prompt**: built-in MTP greedy decode
  tok/s, committed tokens per cycle, the number and mean duration of cycles by
  tokens committed (1, 2 or 3), and prefill tok/s with MTP on;
- **MTP, copy prompt** (`mtp-copy`), only when the user selects it: the MTP
  metrics on an edit in plain text whose continuation repeats a file of the
  prompt. It has no cell in the record row.

#### Scenario: Default run
- **WHEN** the harness runs with no kind selection
- **THEN** the summary reports every metric above for both MTP prompts, and no copy run starts

#### Scenario: Copy kind on request
- **WHEN** the user selects the copy kind
- **THEN** its MTP metrics are reported as detail, and the record row keeps its cells

#### Scenario: Prefill-only change
- **WHEN** the user selects only the plain kind
- **THEN** no MTP run starts and the freed budget goes to more plain quads
