# {{ cookiecutter.project_name }} - pipeline guide

Operational documentation for this Snakemake pipeline, scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).
Defaults are tuned for **Wynton SGE** (used by UCSF and Gladstone) with a stub
profile for **UCSF CoreHPC (Slurm)**. Users on other SGE clusters can run it
with a small set of documented edits (SGE accounting path and Apptainer bind
paths).

## Prerequisites

- [uv](https://docs.astral.sh/uv/) for Python env management
- Docker (for local runs **and** for building any custom container images) **or** Apptainer (for HPC runs only; not used to build images)
- A DockerHub account if you want to push custom images (optional)

## Setup

```bash
uv sync
```

All pipeline commands below are prefixed with `uv run`, which runs each command with the project's `.venv` on `$PATH` (no `source .venv/bin/activate` needed) and keeps deps in sync with `pyproject.toml`. If you prefer the activate flow, `source .venv/bin/activate` once and drop the `uv run` prefix.

Edit `workflow/config/config.yaml` and add samples to `workflow/config/samples.tsv` (columns: `sample_id`, `description`, plus whatever your rules need).

## Quickstart: run the hello-world example

The template ships with a single `hello` rule that writes a greeting per sample. It exercises every execution mode without you writing any code.

```bash
uv run ./workflow/test_pipeline.sh dry-run        # resolve the DAG
uv run ./workflow/test_pipeline.sh run            # run locally in Docker (uses public alpine by default)
uv run ./workflow/test_pipeline.sh run-apptainer  # run locally with Apptainer
```

Outputs land in `.tests/integration/results/<sample>/hello.txt`.

## Building your own container

Image building happens **outside** a pipeline run, ahead of time. Snakemake rules don't build images — they consume them (via `docker run` in Docker mode, or by Apptainer pulling a `.sif` in HPC mode). Building requires a working **Docker** install; Apptainer is only used at runtime on HPC.

The lifecycle for a custom image:

1. **Edit the Dockerfile** at `workflow/containers/<name>/Dockerfile`. The `LABEL version="X.Y.Z"` line is the single source of truth for the image version — `build.sh` reads it to tag the build, and the config file's `tag:` field below must match.
2. **Build** locally (the `build` subcommand only shells out to `docker build`, so the `uv run` prefix is optional here):
   ```bash
   ./workflow/test_pipeline.sh build <name>            # one image
   ./workflow/test_pipeline.sh build                   # every image under workflow/containers/
   ./workflow/test_pipeline.sh build <name> --no-cache # force rebuild
   ```
3. **Push** to DockerHub. Required before any HPC run, since Apptainer pulls the `.sif` from a registry:
   ```bash
   ./workflow/test_pipeline.sh build <name> --push
   ```
4. **Update configs** so the rules consume the image you just built:
   - In `workflow/config/test_config.yaml`, replace the public-alpine quickstart values under `containers.images.hello` with `user: "{{ cookiecutter.docker_username }}"`, `name: "hello"`, `tag: "<version>"` (the swap is documented inline in that file).
   - Bump `tag:` in `workflow/config/config.yaml` (and any `*_wynton.yaml`) every time you bump `LABEL version` in the Dockerfile. Mismatch = pipeline silently runs the old image.

The `docker_username` you supplied at cookiecutter time is baked into both `build.sh` (the `IMAGE=` line) and `config.yaml` (`user:` field). Change both if you retarget another registry.

## Running on Wynton SGE

```bash
ssh log1.wynton.ucsf.edu
cd <your clone>
uv sync
./workflow/test_pipeline.sh build --push          # optional: push custom images first
uv run ./workflow/test_pipeline.sh dry-run-sge
uv run ./workflow/test_pipeline.sh run-sge
```

Wynton defaults are baked in: `/opt/sge/wynton/common/accounting` for qacct status checks (overridable via the `SGE_ACCOUNTING` env var for non-Wynton SGE sites), `--bind /scratch` for Apptainer, and `mem_free` resource semantics accounted for per-slot in `workflow/profiles/sge/config.yaml`.

Non-Gladstone Wynton users: see `workflow/config/config_wynton.yaml.example` for the one place where `/gladstone/bioinformatics` appears (bind paths) — edit to match your storage.

## Running on UCSF CoreHPC (Slurm) — experimental

See [`../workflow/profiles/slurm/README.md`](../workflow/profiles/slurm/README.md). The profile ships as a TODO stub; it has not been validated against CoreHPC. Expect to fill in `slurm_account`, `slurm_partition`, and bind paths.

## Adding a new rule

1. Create `workflow/rules/<name>.smk` with your rule definition. Use `docker_run()` and `get_container_path()` from `common.smk` so it runs in all modes.
2. Add `include: "rules/<name>.smk"` to `workflow/Snakefile`.
3. Expand the `rule all` inputs to cover the new outputs.
4. If it needs custom resources on SGE, add a block under `set-resources:` in `workflow/profiles/sge/config.yaml`.

## Adding a new container

1. `mkdir workflow/containers/<name>` and add a `Dockerfile` with a `LABEL version="..."`.
2. Copy `workflow/containers/hello/build.sh` into the new dir and change `IMAGE=` to `{{ cookiecutter.docker_username }}/<name>`.
3. Register it under `containers.images.<name>` in `workflow/config/config.yaml` and `test_config.yaml`. Set `tag:` to match the Dockerfile's `LABEL version`.
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
