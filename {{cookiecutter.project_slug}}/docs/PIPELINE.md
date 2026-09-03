# {{ cookiecutter.project_name }} - pipeline guide

Operational documentation for this Snakemake pipeline, scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).
Defaults are tuned for **UCSF CoreHPC (Slurm, with GPU)**, the supported
cluster path, and validated end-to-end. **Wynton SGE is deprecated** — the
profile still works and is documented below for existing pipelines, but it is
unmaintained. Users on another Slurm (or SGE) site can run this with a small set
of documented edits (Slurm account or accounting path, and Apptainer bind
paths).

> Using a coding agent to wire your existing scripts into the pipeline? Point it at
> [`../AGENTS.md`](../AGENTS.md) - it covers the rule conventions and the checklist of
> questions to answer before adding a rule.

## How containers and resources are wired

The same rule runs unchanged across four modes (local Docker, local Apptainer,
CoreHPC Slurm, and deprecated Wynton SGE). Two helpers in `workflow/rules/common.smk` make that
work; Snakemake's `container:` directive is **not** used:

- **`docker_run("img")`** expands to a `docker run ...` prefix in Docker mode, `""` otherwise.
- **`apptainer_run("img", gpu=...)`** expands to an `apptainer exec ...` prefix in Apptainer mode, `""` otherwise. With both empty (host mode) the command runs directly.

Per-rule compute resources live in the `resources:` block of
`workflow/config/config.yaml` as canonical units (`threads`, `mem_gb`,
`runtime_min`). `common.smk:_resources()` translates them to SGE or Slurm keys
based on the active profile, so you specify a rule's needs once. Those numbers
start as guesses; once a run has produced `benchmark:` files, replace them with
observations:

```bash
uv run python workflow/scripts/calibrate_resources.py --output_dir results
```

Two more per-rule conventions every rule follows (see `hello.smk`):

- **The script is an `input:`** — `script=script_path("my_step.R")`, invoked as
  `{input.script}`. Snakemake's `code` rerun trigger only watches the rule's shell
  directive, not the file it calls, so without this an edited script silently reuses
  stale outputs.
- **A persistent `log:`** at `{output_dir}/logs/{rule}/{wildcards}.log`, written with
  `... 2>&1 | tee {log}`. Scheduler job logs are transient (the Slurm executor deletes
  them on success). Note `tee` truncates and the path is keyed by rule + wildcards rather
  than by attempt, so the file holds only the **last** run of that job — a rerun
  overwrites the failure that sent you there. If a driver's scrollback reports a failure
  above a log body that ends cleanly, check the timestamps and the snakemake log named in
  the error block.

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

## Running on UCSF CoreHPC (Slurm)

```bash
ssh <you>@plog1.cmf.ucsf.edu      # a CoreHPC login node
cd <your clone>
uv sync
cp workflow/config/config_corehpc.yaml.example workflow/config/config_corehpc.yaml  # edit paths
uv run ./workflow/test_pipeline.sh dry-run-slurm   # validate DAG with the hello example
uv run ./workflow/test_pipeline.sh run-slurm       # hello example, submitted to Slurm

# Real runs: submit snakemake ITSELF as a driver job (see below).
./workflow/launch.sh all check                     # dry-run, submit nothing
./workflow/launch.sh all                           # pre-pull images + submit driver
```

**Never run a long snakemake from a CoreHPC login shell.** The login node reaps
your processes when the SSH session drops (tmux included), so
`workflow/launch.sh` submits the orchestrator as its own Slurm job, which then
submits the step jobs from a compute node. It also pre-pulls the `.sif` files on
the login node — compute nodes have no outbound internet, which is why the
CoreHPC config sets `containers.auto_pull: false` — and keeps the uv and
Apptainer caches off `$HOME`, whose quota is small enough that an image pull
fills it and then breaks `uv run`. Add one entry to its `scope_setup` table per
way you actually run the pipeline. Stop a driver gracefully with
`scancel --signal=TERM <jobid>`.

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

## Running on Wynton SGE (deprecated)

> **Deprecated and unmaintained.** Wynton / SGE still works and is kept for
> pipelines that already run there, but CoreHPC Slurm is the supported cluster
> path — validation, fixes and new features go there. `dry-run-sge` / `run-sge`
> print a warning to this effect. Don't start new work on this path.

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

## Adding a new rule

(Wiring in existing scripts with a coding agent? See [`../AGENTS.md`](../AGENTS.md) for the
full procedure and the questions to answer first.)

1. Create `workflow/rules/<name>.smk`. Give it `params.docker = docker_run("<image>")` and `params.apptainer = apptainer_run("<image>", gpu=...)`, `input.script = script_path("<file>")`, `threads: _threads("<name>")`, `resources: **_resources("<name>", gpu=...)`, a `benchmark:` and a `log:`. Copy `hello.smk`'s shape.
2. Add a `<name>:` entry under `resources:` in `workflow/config/config.yaml` (`threads`, `mem_gb`, `runtime_min`, optional `scratch_gb`). `_resources()`/`_threads()` read it for every scheduler.
3. Add `include: "rules/<name>.smk"` to `workflow/Snakefile` and expand `rule all` to cover the new outputs.
4. For on-cluster tuning that must differ from the config defaults, add a block under the commented `set-resources:` in the relevant profile.

## Adding a new container

1. `mkdir workflow/containers/<name>` and add a `Dockerfile` with a `LABEL version="..."`.
2. Copy `workflow/containers/hello/build.sh` into the new dir and change `IMAGE=` to `{{ cookiecutter.docker_username }}/<name>`.
3. Register it under `containers.images.<name>` in `workflow/config/config.yaml` and `test_config.yaml`. Set `tag:` to match the Dockerfile's `LABEL version`.
4. End the Dockerfile with a verification `RUN` that loads every package the rules need (and asserts the base image version, if you build `FROM` your own image) — a failed install otherwise ships silently and only fails inside a cluster job.
5. `./workflow/test_pipeline.sh build <name>` to build; `--push` when ready. Then confirm the tag actually landed: `docker manifest inspect {{ cookiecutter.docker_username }}/<name>:<tag>`.
6. Before a cluster run, `uv run ./workflow/test_pipeline.sh prepull <config>` on the login node to fetch the `.sif`.

## Project layout

```
workflow/
├── Snakefile                 # orchestration; onstart/onsuccess/onerror hooks
├── rules/
│   ├── common.smk            # sample loader, docker_run/apptainer_run, _resources, notifications
│   ├── containers.smk        # pull_container localrule (pre-pull SIFs on a login node)
│   └── hello.smk             # example rule (copy its shape for new rules)
├── config/
│   ├── config.yaml                    # production (resources: + gpu: blocks)
│   ├── test_config.yaml               # local Docker
│   ├── test_config_apptainer.yaml     # overlay for local/SGE Apptainer
│   ├── test_config_apptainer_slurm.yaml  # overlay for CoreHPC Slurm
│   ├── config_corehpc.yaml.example    # CoreHPC Slurm production
│   └── config_wynton.yaml.example     # Wynton SGE production (DEPRECATED)
├── profiles/
│   ├── local/                # Docker executor
│   ├── apptainer-dev/        # Apptainer on a dev node
│   ├── slurm/                # CoreHPC Slurm (supported; GPU validated)
│   └── sge/                  # Wynton SGE (DEPRECATED, unmaintained)
├── containers/
│   └── hello/                # Dockerfile + build.sh
├── scripts/
│   ├── hello.sh              # example script, declared as the hello rule's input
│   ├── calibrate_resources.py  # suggest resources: values from benchmark TSVs
│   └── resolve_sifs.py       # config -> .sif paths (used by prepull)
├── launch.sh                 # submit a cluster run as a Slurm driver job
└── test_pipeline.sh          # entry-point CLI
```

## Troubleshooting

- **Email notifications**: set `notification.email` in your config. `send_notification()` needs `mail` or `sendmail` on the host — deprecated Wynton log nodes have it, **CoreHPC nodes do not** (and compute nodes have no internet to reach a relay). On CoreHPC use the driver job's Slurm mail instead: `launch.sh` passes `--mail-type=END,FAIL --mail-user=<your config email>` to sbatch, and the controller sends it. Verify with `scontrol show config | grep -i mailprog`; details in [`../workflow/profiles/slurm/README.md`](../workflow/profiles/slurm/README.md).
- **Did the run finish?**: every run writes `{output_dir}/logs/status/latest.txt` (`SUCCESS` / `FAILED` + timestamp) from `onsuccess` / `onerror`. It needs no MTA, network or scheduler, so it works everywhere — `cat` it, or poll it over SSH from a machine that does have internet if you want a push notification.
- **First Apptainer run is slow**: the `onstart` hook auto-pulls any missing `.sif` files into `containers.dir`. Disable with `containers.auto_pull: false` in config if you manage SIFs yourself.
- **SGE jobs show "success" but outputs missing** (deprecated path): `workflow/profiles/sge/status.sh` consults `qacct` precisely to avoid this — confirm `SGE_ACCOUNTING` is readable from your submission host.
- **A Slurm job sits in `PD` forever**: read the reason in `squeue`. `(PartitionTimeLimit)` means the walltime request exceeds the partition MaxTime (`scontrol show partition <p>`); `(Resources)` can mean no node has that much memory. Neither ever fails on its own — cap `runtime_min` at MaxTime and `max_node_mem_gb` at the largest node.
- **`Failed to initialize cache ... Disk quota exceeded`**: the uv or Apptainer cache is in `$HOME`. Point `UV_CACHE_DIR` / `APPTAINER_CACHEDIR` at project storage (`launch.sh` does this for you).
- **A cheap rule wants to rebuild the whole pipeline**: an intermediate is missing, or a killed job left a `Forced execution` flag. `--rerun-triggers mtime` cannot prevent either. Dry-run and read the job table before submitting; `launch.sh`'s guarded scopes do that automatically.
- **An edited script did not rerun its rule**: the rule is missing `script=script_path(...)` in its `input:`.
- **Stale lock after a killed driver**: `uv run snakemake --snakefile workflow/Snakefile --configfile <cfg> --unlock`. Prefer `scancel --signal=TERM` so it exits cleanly instead.
