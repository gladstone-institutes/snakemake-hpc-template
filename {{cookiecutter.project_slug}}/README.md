# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).

Pipeline-specific operational docs (setup, running locally, Wynton SGE,
CoreHPC Slurm, container building, troubleshooting) live in
[`docs/PIPELINE.md`](docs/PIPELINE.md).

## Quickstart

```bash
uv sync
source .venv/bin/activate
./workflow/test_pipeline.sh dry-run    # resolve the DAG
./workflow/test_pipeline.sh run        # run the hello-world example in Docker
```

See [`docs/PIPELINE.md`](docs/PIPELINE.md) for the rest.
