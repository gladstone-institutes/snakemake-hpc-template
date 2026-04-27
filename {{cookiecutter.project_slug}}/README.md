# {{ cookiecutter.project_name }}

A Snakemake pipeline scaffolded from [snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template). Defaults are tuned for **Wynton SGE** (used by UCSF and Gladstone) with a stub profile for **UCSF CoreHPC (Slurm)**. Users on other SGE clusters can run it with a small set of documented edits (SGE accounting path and Apptainer bind paths).

## Prerequisites

- [uv](https://docs.astral.sh/uv/) for Python env management
- Docker (for local runs **and** for building any custom container images) **or** Apptainer (for HPC runs only; not used to build images)
- A DockerHub account if you want to push custom images (optional)

## Setup

```bash
uv sync
source .venv/bin/activate
```

Edit `workflow/config/config.yaml` and add samples to `workflow/config/samples.tsv` (columns: `sample_id`, `description`, plus whatever your rules need).

## Quickstart: run the hello-world example

The template ships with a single `hello` rule that writes a greeting per sample. It exercises every execution mode without you writing any code.

```bash
./workflow/test_pipeline.sh dry-run        # resolve the DAG
./workflow/test_pipeline.sh run            # run locally in Docker (uses public alpine by default)
./workflow/test_pipeline.sh run-apptainer  # run locally with Apptainer
```

Outputs land in `.tests/integration/results/<sample>/hello.txt`.

## Building your own container

Image development assumes a working **Docker** install on the host where you run `build`. Apptainer is used only at *runtime* on HPC (it pulls the image you pushed to DockerHub) and is not used to build images here.

```bash
./workflow/test_pipeline.sh build           # build every Dockerfile under workflow/containers/
./workflow/test_pipeline.sh build hello     # build just the hello image
./workflow/test_pipeline.sh build --push    # build + push to DockerHub
```

The version tag is read from `LABEL version="..."` in the Dockerfile.

Once you've pushed a custom `hello` image, switch `workflow/config/test_config.yaml` from the public alpine fallback (commented at the top of the `containers.images.hello` block) to `user: "{{ cookiecutter.docker_username }}"`.

## Running on Wynton SGE

```bash
ssh log1.wynton.ucsf.edu
cd <your clone>
uv sync
./workflow/test_pipeline.sh build --push    # optional: push custom images first
./workflow/test_pipeline.sh dry-run-sge
./workflow/test_pipeline.sh run-sge
```

Wynton defaults are baked in: `/opt/sge/wynton/common/accounting` for qacct status checks (overridable via the `SGE_ACCOUNTING` env var for non-Wynton SGE sites), `--bind /scratch` for Apptainer, and `mem_free` resource semantics accounted for per-slot in `workflow/profiles/sge/config.yaml`.

Non-Gladstone Wynton users: see `workflow/config/config_wynton.yaml.example` for the one place where `/gladstone/bioinformatics` appears (bind paths) — edit to match your storage.

## Running on UCSF CoreHPC (Slurm) — experimental

See [`workflow/profiles/slurm/README.md`](workflow/profiles/slurm/README.md). The profile ships as a TODO stub; it has not been validated against CoreHPC. Expect to fill in `slurm_account`, `slurm_partition`, and bind paths.

## Adding a new rule

1. Create `workflow/rules/<name>.smk` with your rule definition. Use `docker_run()` and `get_container_path()` from `common.smk` so it runs in all modes.
2. Add `include: "rules/<name>.smk"` to `workflow/Snakefile`.
3. Expand the `rule all` inputs to cover the new outputs.
4. If it needs custom resources on SGE, add a block under `set-resources:` in `workflow/profiles/sge/config.yaml`.

## Adding a new container

1. `mkdir workflow/containers/<name>` and add a `Dockerfile` with a `LABEL version="..."`.
2. Copy `workflow/containers/hello/build.sh` into the new dir and change `IMAGE=`.
3. Register it under `containers.images.<name>` in `workflow/config/config.yaml` and `test_config.yaml`.
4. `./workflow/test_pipeline.sh build <name>` to build; `--push` when ready.

## Project layout

```
workflow/
├── Snakefile                 # orchestration; onstart/onsuccess/onerror hooks
├── rules/
│   ├── common.smk            # sample loader, container helpers, notifications
│   └── hello.smk             # example rule
├── config/
│   ├── config.yaml           # production
│   ├── test_config.yaml      # local Docker
│   ├── test_config_apptainer.yaml
│   └── config_wynton.yaml.example
├── profiles/
│   ├── local/                # Docker executor
│   ├── apptainer-dev/        # Apptainer on a dev node
│   ├── sge/                  # Wynton SGE (working)
│   └── slurm/                # CoreHPC Slurm (stub)
├── containers/
│   └── hello/                # Dockerfile + build.sh
└── test_pipeline.sh          # entry-point CLI
```

## Troubleshooting

- **Email notifications**: set `notification.email` in your config. Requires `mail` or `sendmail` on the host. Wynton log nodes have it.
- **First Apptainer run is slow**: the `onstart` hook auto-pulls any missing `.sif` files into `containers.dir`. Disable with `containers.auto_pull: false` in config if you manage SIFs yourself.
- **SGE jobs show "success" but outputs missing**: `workflow/profiles/sge/status.sh` consults `qacct` precisely to avoid this — confirm `SGE_ACCOUNTING` is readable from your submission host.
