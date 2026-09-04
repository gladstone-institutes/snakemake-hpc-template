# snakemake-hpc-template

A cookiecutter template for Snakemake + uv pipelines, built for **UCSF / Gladstone HPC**.
You write each rule once. The same workflow then runs in a container on your laptop or on
the cluster, and the generated docs explain containers from scratch for people new to them.

<img src="%7B%7Bcookiecutter.project_slug%7D%7D/docs/containers.svg" alt="Container lifecycle: build with Docker on a laptop, push to a registry, run with Apptainer on the cluster" width="640">

| Where | Container runtime | Command |
|---|---|---|
| Laptop | Docker | `./workflow/test_pipeline.sh run` |
| Laptop or dev node | Apptainer | `./workflow/test_pipeline.sh run-apptainer` |
| **UCSF CoreHPC (Slurm)**, GPU validated | Apptainer | `./workflow/launch.sh all` |
| Wynton (SGE), **deprecated and unmaintained** | Apptainer | `./workflow/test_pipeline.sh run-sge` |

CoreHPC defaults are validated end to end (`hpc_core` account, `/mnt/scratch` bind,
`small_gpu` / L40s routing) and include a driver-job launcher for runs too long to drive
from a login shell. Other Slurm sites adjust a few values listed in the generated
`docs/PIPELINE.md`.

## Quickstart

```bash
pip install cookiecutter        # or: uv tool install cookiecutter
cookiecutter gh:gladstone-institutes/snakemake-hpc-template
# or from a local clone:
cookiecutter /path/to/snakemake-hpc-template
```

Cookiecutter prompts for seven values:

| Variable | Example |
|---|---|
| `project_name` | `My Snakemake Pipeline` |
| `project_slug` | auto-derived from `project_name` |
| `author_name` | `Jane Scientist` |
| `author_email` | `jane@gladstone.ucsf.edu` |
| `docker_username` | `jscientist` |
| `python_version` | `3.11` |
| `notification_email` | defaults to `author_email` |

Then:

```bash
cd my-snakemake-pipeline
uv sync
uv run ./workflow/test_pipeline.sh dry-run    # DAG resolves
uv run ./workflow/test_pipeline.sh run        # runs the hello-world example in Docker
```

## Wiring in your own workflow

Once the hello-world example runs, swap it for your real pipeline. The generated project
ships an `AGENTS.md` that turns existing R, Python, or bash scripts into rules, with the
checklist to work through before adding each one. Point a coding agent (Claude Code,
Cursor) at it, or follow it yourself.

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
├── AGENTS.md                 # guide for wiring existing scripts into rules
├── docs/PIPELINE.md          # setup, containers, CoreHPC, troubleshooting
├── workflow/
│   ├── Snakefile, rules/     # one example rule; common.smk holds the helpers
│   ├── config/               # config.yaml (resources:/gpu:), samples.tsv, cluster examples
│   ├── profiles/             # local, apptainer-dev, slurm, sge
│   ├── containers/           # one Dockerfile + build.sh per image
│   ├── launch.sh             # submit a cluster run as a Slurm driver job
│   └── test_pipeline.sh      # dry-run | run | run-apptainer | run-slurm | prepull | build
└── tests/                    # pytest smoke tests
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
