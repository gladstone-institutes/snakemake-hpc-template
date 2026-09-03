# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).

Pipeline-specific operational docs (setup, running locally, CoreHPC Slurm with
GPU, container building, troubleshooting) live in
[`docs/PIPELINE.md`](docs/PIPELINE.md). A deprecated, unmaintained Wynton SGE
profile is still included and documented there.

## Quickstart

```bash
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # resolve the DAG
uv run ./workflow/test_pipeline.sh run        # run the hello-world example in Docker
```

`uv run` keeps deps in sync with `pyproject.toml` and runs each command with the project's `.venv` on `$PATH`, so there's no `activate` step.

On a cluster, submit snakemake **itself** as a job rather than running it from a login shell (which gets reaped when your SSH session drops):

```bash
uv run ./workflow/test_pipeline.sh prepull <config>   # login node: fetch .sif files
./workflow/launch.sh all check                        # dry-run, submit nothing
./workflow/launch.sh all                              # submit the driver job
```

## Wiring in your own scripts

To replace the hello-world example with your real pipeline, see [`AGENTS.md`](AGENTS.md): a step-by-step guide for turning existing R / Python / bash scripts into rules (written for coding agents such as Claude Code or Cursor, but worth reading yourself), including the questions to answer before adding each rule.

See [`docs/PIPELINE.md`](docs/PIPELINE.md) for the rest.
