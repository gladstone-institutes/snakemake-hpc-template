# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).

Pipeline-specific operational docs (setup, running locally, Wynton SGE,
CoreHPC Slurm with GPU, container building, troubleshooting) live in
[`docs/PIPELINE.md`](docs/PIPELINE.md).

## Quickstart

```bash
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # resolve the DAG
uv run ./workflow/test_pipeline.sh run        # run the hello-world example in Docker
```

`uv run` keeps deps in sync with `pyproject.toml` and runs each command with the project's `.venv` on `$PATH`, so there's no `activate` step.

## Wiring in your own scripts

To replace the hello-world example with your real pipeline, see [`AGENTS.md`](AGENTS.md): a step-by-step guide for turning existing R / Python / bash scripts into rules (written for coding agents such as Claude Code or Cursor, but worth reading yourself), including the questions to answer before adding each rule.

See [`docs/PIPELINE.md`](docs/PIPELINE.md) for the rest.
