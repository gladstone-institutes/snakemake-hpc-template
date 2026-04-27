# snakemake-hpc-template

A cookiecutter template for Snakemake + uv pipelines, optimized for **UCSF / Gladstone HPC** users.

- **Wynton HPC (SGE)** — fully supported, tested defaults (accounting path, scratch bind, notification email).
- **UCSF CoreHPC (Slurm)** — stub profile ships with TODOs; not yet validated.
- **Local Docker or Apptainer** — one-command `./workflow/test_pipeline.sh run` works on a laptop.
- **Optional local image building** — `./workflow/test_pipeline.sh build [--push]` wraps every `workflow/containers/*/build.sh`. Image development assumes Docker; Apptainer is used only to *run* prebuilt images on HPC.
- **uv-managed Python environment** — fast, lock-file-backed.

Users on other SGE clusters are welcome; the generated project's README documents the small set of paths to adjust — `SGE_ACCOUNTING` (env var consumed by `profiles/sge/status.sh`) and the Apptainer bind paths in `config_wynton.yaml.example`. Gladstone-specific defaults (the `/gladstone/bioinformatics` bind) are flagged inline in that example file.

## Quickstart

```bash
pip install cookiecutter        # or: uv tool install cookiecutter
cookiecutter gh:gladstone-institutes/snakemake-hpc-template
# or from a local clone:
cookiecutter /path/to/snakemake-hpc-template
```

Cookiecutter will prompt for seven values:

| Variable | Example |
|---|---|
| `project_name` | `My Snakemake Pipeline` |
| `project_slug` | auto-derived from `project_name` |
| `author_name` | `Jane Scientist` |
| `author_email` | `jane@gladstone.ucsf.edu` |
| `docker_username` | `jscientist` |
| `python_version` | `3.11` |
| `wynton_account_email` | defaults to `author_email` |

After generation:

```bash
cd my-snakemake-pipeline
uv sync
source .venv/bin/activate
./workflow/test_pipeline.sh dry-run    # DAG resolves
./workflow/test_pipeline.sh run        # runs the hello-world example in Docker
```

## What's in the generated project

```
my-snakemake-pipeline/
├── pyproject.toml                # snakemake, pandas, pyarrow, pyyaml + pytest
├── workflow/
│   ├── Snakefile                 # onstart/onsuccess/onerror hooks wired
│   ├── rules/
│   │   ├── common.smk            # sample loader, docker_run(), container helpers, notifications
│   │   └── hello.smk             # one example rule
│   ├── config/                   # test_config.yaml (Docker), config.yaml (production), etc.
│   ├── profiles/
│   │   ├── local/                # Docker executor
│   │   ├── apptainer-dev/        # Apptainer on a laptop/dev node
│   │   ├── sge/                  # Wynton SGE (working)
│   │   └── slurm/                # CoreHPC Slurm (stub; TODOs)
│   ├── containers/
│   │   └── hello/                # Dockerfile + build.sh
│   └── test_pipeline.sh          # dry-run | run | run-apptainer | run-sge | build | ...
└── tests/                        # pytest smoke tests
```

## Development

```bash
pip install pytest pytest-cookies
pytest tests/
```

`tests/test_bake.py` bakes the template into a tmpdir and asserts that core files exist.
`tests/test_hello_dryrun.sh` bakes and runs `./workflow/test_pipeline.sh dry-run` end-to-end.

## License

MIT
