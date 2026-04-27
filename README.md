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
| `notification_email` | defaults to `author_email` |

After generation:

```bash
cd my-snakemake-pipeline
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # DAG resolves
uv run ./workflow/test_pipeline.sh run        # runs the hello-world example in Docker
```

`uv run` syncs the env on demand and runs the script with the project's `.venv` on `$PATH`, so you don't need `source .venv/bin/activate`.

## Scaffolding into an existing repo

If you already have a pipeline repo and want to add this scaffolding without overwriting your existing `README.md`, `pyproject.toml`, etc., use cookiecutter's `--overwrite-if-exists` + `--skip-if-file-exists` flags. Run **from inside your existing repo** with `--output-dir ..` so cookiecutter renders into your repo (not a nested subdirectory):

```bash
cd /path/to/your-existing-repo
cookiecutter gh:gladstone-institutes/snakemake-hpc-template \
    --output-dir .. \
    --overwrite-if-exists --skip-if-file-exists \
    project_slug="$(basename "$PWD")"
```

Cookiecutter always writes to `<output-dir>/<project_slug>/`. Setting `--output-dir ..` and `project_slug=<your-repo-dir-name>` makes that path resolve back to your current directory. **Do not run with `--output-dir .` from inside the repo** — that produces a nested `<repo>/<repo>/` tree.

Files that already exist in your repo are preserved; everything new (including the pipeline-specific docs at `docs/PIPELINE.md`) lands cleanly. The post-gen hook detects an existing `.git` and skips the initial-commit step. Review the new files with `git status` and commit selectively.

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
