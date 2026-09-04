# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).
Each rule runs inside a container, on a laptop with Docker or on the cluster with
Apptainer. [`docs/PIPELINE.md`](docs/PIPELINE.md) explains that model from scratch and
covers setup, CoreHPC Slurm with GPU, building images, and troubleshooting.

## Quickstart

```bash
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # resolve the DAG
uv run ./workflow/test_pipeline.sh run        # run the hello-world example in Docker
```

`uv run` keeps deps in sync with `pyproject.toml` and runs each command with the project's
`.venv` on `$PATH`, so there is no `activate` step.

On CoreHPC, submit snakemake itself as a job (why: [`docs/PIPELINE.md`](docs/PIPELINE.md)):

```bash
uv run ./workflow/test_pipeline.sh prepull <config>   # login node: fetch .sif files
./workflow/launch.sh all check                        # dry-run, submit nothing
./workflow/launch.sh all                              # submit the driver job
```

## Wiring in your own scripts

To replace the hello-world example with your real pipeline, see [`AGENTS.md`](AGENTS.md).
It walks through turning existing R / Python / bash scripts into rules and lists the
questions to answer before adding each one. Written for coding agents, readable by humans.
