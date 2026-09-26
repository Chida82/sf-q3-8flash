# Spec Delta

## ADDED Requirements

### Requirement: Generation length override
The harness SHALL accept a generation length that replaces, for every selected
kind, the number of tokens generated at each frontier (64 for plain, 128 for
the MTP kinds). The metric names, the correctness gate and the schedule SHALL
stay the same. The summary header SHALL show the override. A summary made with
an override SHALL print no record row, because its decode figures are not
comparable with the rows of the performance record; it SHALL say so in place
of the row. A length below 16 or above 4096 SHALL be refused before any run.

#### Scenario: Longer decode phases
- **WHEN** the harness runs with a generation length of 512
- **THEN** every bench run generates 512 tokens per frontier and the summary header names the override

#### Scenario: No record row
- **WHEN** a summary was made with a generation length override
- **THEN** it prints no record row and states that the override suppressed it

#### Scenario: Length out of range
- **WHEN** the generation length is 8
- **THEN** the harness exits with a usage error before any run
