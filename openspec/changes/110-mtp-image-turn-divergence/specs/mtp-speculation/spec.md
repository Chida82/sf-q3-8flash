# Spec Delta

## ADDED Requirements

### Requirement: Greedy identity holds across turns and images
In an interactive conversation, greedy decoding with built-in MTP SHALL commit, in every turn, exactly the tokens that plain greedy decoding commits for the same model, context and conversation. This SHALL hold for text-only conversations and for conversations with images, at the automatic depth and at pinned depths 2 and 3.

#### Scenario: Two-image conversation
- **WHEN** a REPL conversation reads two different images and asks for a description after each, at temperature 0, without and with `--mtp`
- **THEN** every turn of the MTP output is byte-identical to the same turn of the plain output

#### Scenario: Text-only conversation
- **WHEN** a REPL conversation of four text user turns runs without and with `--mtp` at temperature 0
- **THEN** every turn of the MTP output is byte-identical to the plain output

### Requirement: Multi-turn identity is checked
The repository SHALL provide a check that runs one REPL conversation without and with built-in MTP, compares the outputs turn by turn, names the first differing turn and line, and exits with a failure status on any difference.

#### Scenario: Identical conversation
- **WHEN** the vision check runs with `--compare` and every turn matches
- **THEN** it reports every turn as identical and exits 0

#### Scenario: A diverging turn
- **WHEN** one turn of the MTP output differs from the plain output
- **THEN** the check names the turn and the first differing line, and exits 1
