# snakemake-hpc-template

A cookiecutter template for Snakemake + uv pipelines, built for **UCSF / Gladstone HPC** users.

The same workflow runs four ways:

- **Wynton HPC (SGE)**, with tested defaults for the accounting path, scratch bind, and notification email.
- **UCSF CoreHPC (Slurm)**, with GPU support and validated defaults (`hpc_core` account, `/mnt/scratch` bind, `small_gpu`/L40s routing).
- **Local Docker or Apptainer** on a laptop, via one command: `./workflow/test_pipeline.sh run`.
- **uv-managed Python**, fast and lock-file-backed.

You can build container images locally too. `./workflow/test_pipeline.sh build [--push]` wraps every `workflow/containers/*/build.sh`. Build with Docker; Apptainer only *runs* prebuilt images on HPC.

On a different SGE or Slurm cluster? You only need to adjust a few values. The generated project's `docs/PIPELINE.md` and `profiles/*/README.md` list them. Gladstone-specific binds (`/gladstone/bioinformatics` and `/mnt/scratch`) are flagged inline in the `config_*.yaml.example` files.

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

`uv run` syncs the environment and runs each command inside the project's `.venv`, so you never need to activate it by hand.

## Wiring in your own workflow

Once the hello-world example runs, swap it for your real pipeline. The generated project ships an `AGENTS.md` that turns your existing R, Python, or bash scripts into Snakemake rules. It includes the checklist to work through before adding each rule. Point a coding agent (Claude Code, Cursor) at `AGENTS.md`, or follow it yourself.

## Scaffolding into an existing repo

Already have a pipeline repo? You can add this scaffolding without overwriting your `README.md`, `pyproject.toml`, and other files. Use cookiecutter's `--overwrite-if-exists` and `--skip-if-file-exists` flags, and run **from inside your repo** with `--output-dir ..` so it renders into your repo rather than a nested subdirectory:

```bash
cd /path/to/your-existing-repo
cookiecutter gh:gladstone-institutes/snakemake-hpc-template \
    --output-dir .. \
    --overwrite-if-exists --skip-if-file-exists \
    project_slug="$(basename "$PWD")"
```

Cookiecutter always writes to `<output-dir>/<project_slug>/`. Setting `--output-dir ..` with `project_slug` as your repo's folder name points that path back at your current directory. **Do not run with `--output-dir .` from inside the repo.** That produces a nested `<repo>/<repo>/` tree.

Your existing files are preserved. Everything new lands cleanly, including the docs at `docs/PIPELINE.md`. The post-gen hook detects an existing `.git` and skips its initial commit. Review the new files with `git status` and commit what you want.

## What's in the generated project

```
my-snakemake-pipeline/
├── pyproject.toml                # snakemake, pandas, pyarrow, pyyaml + pytest
├── AGENTS.md                     # guide for coding agents wiring in existing scripts
├── workflow/
│   ├── Snakefile                 # onstart/onsuccess/onerror hooks wired
│   ├── rules/
│   │   ├── common.smk            # sample loader, docker_run/apptainer_run, _resources, notifications
│   │   └── hello.smk             # one example rule
│   ├── config/                   # config.yaml (resources:/gpu:), test_config.yaml, cluster examples
│   ├── profiles/
│   │   ├── local/                # Docker executor
│   │   ├── apptainer-dev/        # Apptainer on a laptop/dev node
│   │   ├── sge/                  # Wynton SGE (working)
│   │   └── slurm/                # CoreHPC Slurm (working, GPU)
│   ├── containers/
│   │   └── hello/                # Dockerfile + build.sh
│   └── test_pipeline.sh          # dry-run | run | run-apptainer | run-sge | run-slurm | build | ...
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