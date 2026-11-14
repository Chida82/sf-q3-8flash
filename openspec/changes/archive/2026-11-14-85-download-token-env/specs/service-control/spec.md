# Spec Delta

## ADDED Requirements

### Requirement: The Hugging Face token stays out of argv
When `sfctl install` or `sfctl update` links a model through `./download.sh`, a Hugging Face token given with `--token` or `HF_TOKEN` SHALL reach `hf` only through its environment. No process started by the download SHALL carry the token in its arguments.

#### Scenario: Token on the command line of download.sh
- **WHEN** `./download.sh vision --token <value>` runs
- **THEN** `hf download` is started with `HF_TOKEN=<value>` in its environment and without `--token` in its arguments

#### Scenario: No token
- **WHEN** neither `--token` nor `HF_TOKEN` is given
- **THEN** `hf download` runs with its own login and `download.sh` does not read the login file
