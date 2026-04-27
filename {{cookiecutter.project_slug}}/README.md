# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).

Pipeline-specific operational docs (setup, running locally, Wynton SGE,
CoreHPC Slurm, container building, troubleshooting) live in
[`docs/PIPELINE.md`](docs/PIPELINE.md).

## Quickstart

```bash
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # resolve the DAG
uv run ./workflow/test_pipeline.sh run        # run the hello-world example in Docker
```

`uv run` keeps deps in sync with `pyproject.toml` and runs each command with the project's `.venv` on `$PATH`, so there's no `activate` step.

See [`docs/PIPELINE.md`](docs/PIPELINE.md) for the rest.
