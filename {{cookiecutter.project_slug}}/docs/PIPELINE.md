# {{ cookiecutter.project_name }} - pipeline guide

Operational documentation for this Snakemake pipeline, scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).
Defaults are tuned for **Wynton SGE** and **UCSF CoreHPC (Slurm, with GPU)**,
both used at UCSF and Gladstone and both validated end-to-end. Users on other
SGE / Slurm clusters can run it with a small set of documented edits (accounting
path or Slurm account, and Apptainer bind paths).

> Using a coding agent to wire your existing scripts into the pipeline? Point it at
> [`../AGENTS.md`](../AGENTS.md) - it covers the rule conventions and the checklist of
> questions to answer before adding a rule.

## How containers and resources are wired

The same rule runs unchanged across four modes (local Docker, local Apptainer,
Wynton SGE, CoreHPC Slurm). Two helpers in `workflow/rules/common.smk` make that
work; Snakemake's `container:` directive is **not** used:

- **`docker_run("img")`** expands to a `docker run ...` prefix in Docker mode, `""` otherwise.
- **`apptainer_run("img", gpu=...)`** expands to an `apptainer exec ...` prefix in Apptainer mode, `""` otherwise. With both empty (host mode) the command runs directly.

Per-rule compute resources live in the `resources:` block of
`workflow/config/config.yaml` as canonical units (`threads`, `mem_gb`,
`runtime_min`). `common.smk:_resources()` translates them to SGE or Slurm keys
based on the active profile, so you specify a rule's needs once.

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

## Running on UCSF CoreHPC (Slurm)

```bash
ssh <you>@plog1.cmf.ucsf.edu      # a CoreHPC login node
cd <your clone>
uv sync
cp workflow/config/config_corehpc.yaml.example workflow/config/config_corehpc.yaml  # edit paths
uv run ./workflow/test_pipeline.sh dry-run-slurm   # validate DAG with the hello example
uv run ./workflow/test_pipeline.sh run-slurm       # or run real samples via --configfile config_corehpc.yaml
```

The Slurm account/partition defaults (`hpc_core` / `cpu`) are baked into
`workflow/profiles/slurm/config.yaml`; `/mnt/scratch` and your project storage
are bound via `containers.bind_paths`. Full details (resource mapping, the
greedy-scheduler and `gres` gotchas) are in
[`../workflow/profiles/slurm/README.md`](../workflow/profiles/slurm/README.md).

### GPU rules

GPU support is config-driven. To make a rule use a GPU, pass `gpu=True` to both
`apptainer_run()` and `_resources()`:

```python
rule train:
    output: "{output_dir}/{sample}/model.pt"
    params:
        docker=docker_run("mytool"),
        apptainer=apptainer_run("mytool", gpu=True),
        # optional: log nvidia-smi utilization to gpu_usage_train_<jobid>.csv
        gpu_sampler=lambda w, output: gpu_sampler_prefix(
            Path(output[0]).parent, "train", gpu=True),
    threads: _threads("train")
    resources:
        **_resources("train", gpu=True),
    shell:
        "{params.gpu_sampler}{params.docker}{params.apptainer} mytool train ..."
```

On CoreHPC Slurm this routes the job to the GPU partition with `--gres` and adds
`--nv` to Apptainer. The GPU partition / gres come from the `gpu:` block in
`config.yaml` (defaults: `small_gpu` / `gpu:nvidia_l40s:1`). The Slurm profile
caps concurrent GPU jobs at 1 (CoreHPC's per-user limit) — raise it with
`--resources max_concurrent_gpu_jobs=N`. Don't add `--gres` via `slurm_extra`;
it deadlocks the scheduler (see the slurm README).

## Adding a new rule

(Wiring in existing scripts with a coding agent? See [`../AGENTS.md`](../AGENTS.md) for the
full procedure and the questions to answer first.)

1. Create `workflow/rules/<name>.smk`. Give it `params.docker = docker_run("<image>")` and `params.apptainer = apptainer_run("<image>", gpu=...)`, `threads: _threads("<name>")`, and `resources: **_resources("<name>", gpu=...)`. Copy `hello.smk`'s shape.
2. Add a `<name>:` entry under `resources:` in `workflow/config/config.yaml` (`threads`, `mem_gb`, `runtime_min`, optional `scratch_gb`). `_resources()`/`_threads()` read it for every scheduler.
3. Add `include: "rules/<name>.smk"` to `workflow/Snakefile` and expand `rule all` to cover the new outputs.
4. For on-cluster tuning that must differ from the config defaults, add a block under the commented `set-resources:` in the relevant profile.

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
│   ├── common.smk            # sample loader, docker_run/apptainer_run, _resources, notifications
│   └── hello.smk             # example rule (copy its shape for new rules)
├── config/
│   ├── config.yaml                    # production (resources: + gpu: blocks)
│   ├── test_config.yaml               # local Docker
│   ├── test_config_apptainer.yaml     # overlay for local/SGE Apptainer
│   ├── test_config_apptainer_slurm.yaml  # overlay for CoreHPC Slurm
│   ├── config_wynton.yaml.example     # Wynton SGE production
│   └── config_corehpc.yaml.example    # CoreHPC Slurm production
├── profiles/
│   ├── local/                # Docker executor
│   ├── apptainer-dev/        # Apptainer on a dev node
│   ├── sge/                  # Wynton SGE (working)
│   └── slurm/                # CoreHPC Slurm (working, GPU)
├── containers/
│   └── hello/                # Dockerfile + build.sh
└── test_pipeline.sh          # entry-point CLI
```

## Troubleshooting

- **Email notifications**: set `notification.email` in your config. Requires `mail` or `sendmail` on the host. Wynton log nodes have it.
- **First Apptainer run is slow**: the `onstart` hook auto-pulls any missing `.sif` files into `containers.dir`. Disable with `containers.auto_pull: false` in config if you manage SIFs yourself.
- **SGE jobs show "success" but outputs missing**: `workflow/profiles/sge/status.sh` consults `qacct` precisely to avoid this — confirm `SGE_ACCOUNTING` is readable from your submission host.
