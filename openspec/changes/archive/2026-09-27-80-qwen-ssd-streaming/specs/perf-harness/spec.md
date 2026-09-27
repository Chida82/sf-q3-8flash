# Spec Delta

## ADDED Requirements

### Requirement: Bench arguments
The harness SHALL accept bench arguments to pass to both builds' bench runs,
and bench arguments to pass to B's runs only. Both SHALL be named in the
summary header. The correctness gate, the schedule and the metrics SHALL stay
the same, so a B-only argument compares two modes of one build. A summary
made with any bench argument SHALL print no record row, stating why.

#### Scenario: Streamed against resident
- **WHEN** A and B are the same tree and `--ssd-streaming` is a B-only argument
- **THEN** the correctness gate compares streamed tokens with resident tokens and the summary reports the streamed/resident ratios

#### Scenario: Emulated smaller machine
- **WHEN** `--simulate-used-memory 80GB` is passed to both builds
- **THEN** every bench run gets the argument and the header names it

#### Scenario: No record row
- **WHEN** any bench argument was given
- **THEN** the summary prints no record row and says why
