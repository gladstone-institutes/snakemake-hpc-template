# {{ cookiecutter.project_name }} - pipeline guide

How to set up, run, and extend this Snakemake pipeline, scaffolded from
[snakemake-hpc-template](https://github.com/gladstone-institutes/snakemake-hpc-template).
Defaults target **UCSF CoreHPC (Slurm, with GPU)**, the supported and validated cluster path.
Other Slurm sites need a few documented edits (account, partition, bind paths).

> Turning existing scripts into rules, or pointing a coding agent at this repo?
> Start with [`../AGENTS.md`](../AGENTS.md).

## Containers in one minute

New to containers? Here is the whole model this pipeline relies on.

- A **container image** is a frozen software environment: an OS, your tool, its libraries.
  It is described by a `Dockerfile` and identified by `user/name:tag`.
- **Docker** builds images and runs them on your laptop.
- HPC clusters do not allow Docker (it needs root). They use **Apptainer**, which runs the
  same image after converting it to a single `.sif` file. Apptainer can build images of
  its own, but this pipeline builds only with Docker (why: below).
- Images travel through a **registry** (DockerHub): you push from your laptop, the cluster
  pulls. CoreHPC compute nodes have no internet, so the pull happens on a login node first.
- Each rule's command is wrapped in `docker run ...` or `apptainer exec ...` depending on
  `execution.use_docker` / `execution.use_apptainer` in the config. The rule itself never
  changes.

![Container lifecycle: build with Docker, push to a registry, run with Apptainer](containers.svg)

## Prerequisites

- [uv](https://docs.astral.sh/uv/) for the Python environment
- **Docker** for local runs and for building images (the only build path), **or**
  **Apptainer** for cluster runs
- A DockerHub account, only if you build your own images

## Quickstart

```bash
uv sync
uv run ./workflow/test_pipeline.sh dry-run        # resolve the DAG
uv run ./workflow/test_pipeline.sh run            # run locally in Docker
uv run ./workflow/test_pipeline.sh run-apptainer  # run locally with Apptainer
```

The shipped `hello` rule writes one greeting per sample to
`.tests/integration/results/<sample>/hello.txt`. It uses the public `library/bash:5` image,
so no DockerHub account is needed. Bash is required because Snakemake wraps every rule in
`bash -c`; plain `alpine` fails under Apptainer.

For real data, edit `workflow/config/config.yaml` and list samples in
`workflow/config/samples.tsv` (columns `sample_id`, `description`, plus whatever your rules need).

## Running on UCSF CoreHPC (Slurm)

```bash
ssh <you>@plog1.cmf.ucsf.edu      # a CoreHPC login node
cd <your clone>
uv sync
cp workflow/config/config_corehpc.yaml.example workflow/config/config_corehpc.yaml  # edit paths
uv run ./workflow/test_pipeline.sh dry-run-slurm   # validate DAG with the hello example
uv run ./workflow/test_pipeline.sh run-slurm       # hello example, submitted to Slurm

# Real runs: submit snakemake ITSELF as a driver job.
./workflow/launch.sh all check                     # dry-run, submit nothing
./workflow/launch.sh all                           # pre-pull images + submit driver
```

Three things `launch.sh` handles for you, each a real CoreHPC constraint:

- **Login shells are reaped** when your SSH session drops, tmux included. So snakemake runs
  as its own Slurm job (the driver) and submits step jobs from a compute node.
- **Compute nodes have no internet.** Images are pre-pulled on the login node, and the
  CoreHPC config sets `containers.auto_pull: false`.
- **`$HOME` has a small quota.** The uv and Apptainer caches go on project storage instead.

Add one entry to the `scope_setup` table in `launch.sh` per way you run the pipeline. Stop a
driver with `scancel --signal=TERM <jobid>`. Account and partition defaults, resource
mapping, and every cluster gotcha are in
[`../workflow/profiles/slurm/README.md`](../workflow/profiles/slurm/README.md).

### GPU rules

Pass `gpu=True` to both `apptainer_run()` and `_resources()`:

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

On Slurm this routes the job to the GPU partition with `--gres` and adds `--nv` to
Apptainer. Partition and gres come from the `gpu:` block in `config.yaml` (defaults
`small_gpu` / `gpu:nvidia_l40s:1`). Concurrent GPU jobs are capped at 1, CoreHPC's per-user
limit; raise it with `--resources max_concurrent_gpu_jobs=N`.

## Building your own container

Images are built ahead of time, never during a run.

### Why Docker builds, and where images live

- One Dockerfile serves both runtimes. A Docker image runs under Docker on a laptop and
  under Apptainer on the cluster, which converts it on pull. A `.sif` built from an
  Apptainer definition file runs only under Apptainer, so you would maintain two builds.
- Building needs root-like privileges and internet access. A laptop has both. CoreHPC
  compute nodes have neither, and Apptainer's own builds need fakeroot support on the host.
- The registry is the hand-off: push once from the laptop, pull on any machine. Docker's
  layer cache also keeps rebuilds fast after a small Dockerfile change.
- **Private images.** Docker Hub's free Personal plan allows one private repository, with
  unlimited public ones. Pull limits depend on the plan, see
  [Docker Hub usage and limits](https://docs.docker.com/docker-hub/usage/). For more private
  images use a paid Docker plan or another registry such as GitHub Container Registry. Any
  registry works with this template: set `user: "ghcr.io/<org>"` in the config and
  `IMAGE=ghcr.io/<org>/<name>` in `build.sh`. Both simply prepend `user` to the image name.
- Pulling a private image on the cluster needs a login on the **login node** before
  `prepull`: `apptainer registry login --username <you> docker://<registry>`. Compute nodes
  cannot reach the registry at all.

1. **Edit** `workflow/containers/<name>/Dockerfile`. Its `LABEL version="X.Y.Z"` is the
   single source of truth for the tag; `build.sh` reads it.
2. **Build** (plain `docker build` underneath, so `uv run` is optional):
   ```bash
   ./workflow/test_pipeline.sh build <name>            # one image
   ./workflow/test_pipeline.sh build                   # every image under workflow/containers/
   ./workflow/test_pipeline.sh build <name> --no-cache # force rebuild
   ```
3. **Push** to DockerHub. Required before any cluster run, since Apptainer pulls from there:
   ```bash
   ./workflow/test_pipeline.sh build <name> --push
   ```
4. **Point the config at it.** In `workflow/config/test_config.yaml`, replace the
   `library/bash` quickstart values under `containers.images.hello` with
   `user: "{{ cookiecutter.docker_username }}"`, `name: "hello"`, `tag: "<version>"`.
   Bump `tag:` in `workflow/config/config.yaml` every time you bump `LABEL version`.
   A mismatch silently runs the old image.

Your `docker_username` is baked into both `build.sh` (`IMAGE=`) and `config.yaml` (`user:`).
Change both to retarget another registry.

## Adding a new rule

Full conventions and the questions to answer first are in [`../AGENTS.md`](../AGENTS.md).
The short version:

1. Create `workflow/rules/<name>.smk` by copying the shape of
   [`../workflow/rules/hello.smk`](../workflow/rules/hello.smk): both container params, the
   script as an `input:`, `_threads` / `_resources`, a `benchmark:` and a `log:`.
2. Add a `<name>:` entry under `resources:` in `workflow/config/config.yaml`
   (`threads`, `mem_gb`, `runtime_min`, optional `scratch_gb`).
3. Add `include: "rules/<name>.smk"` to `workflow/Snakefile` and extend `rule all`.
4. For on-cluster overrides only, use the commented `set-resources:` block in the profile.

## Adding a new container

1. `mkdir workflow/containers/<name>` and add a `Dockerfile` with a `LABEL version="..."`.
   End it with a verification `RUN` that loads every package the rules need, so a failed
   install fails the build rather than a cluster job.
2. Copy `workflow/containers/hello/build.sh` into the new dir and set
   `IMAGE={{ cookiecutter.docker_username }}/<name>`.
3. Register it under `containers.images.<name>` in `config.yaml` and `test_config.yaml`,
   with `tag:` matching the `LABEL version`.
4. `./workflow/test_pipeline.sh build <name>`, then `--push`. Confirm the tag landed:
   `docker manifest inspect {{ cookiecutter.docker_username }}/<name>:<tag>`.
5. Before a cluster run: `uv run ./workflow/test_pipeline.sh prepull <config>` on a login node.

## How it is wired

Two helpers in `workflow/rules/common.smk` make one Snakefile run in every mode. Snakemake's
`container:` directive is deliberately **not** used.

- `docker_run("img")` returns a `docker run ...` prefix in Docker mode, else `""`.
- `apptainer_run("img", gpu=...)` returns an `apptainer exec ...` prefix in Apptainer mode,
  else `""`. With both empty the command runs on the host.

Resources are config-driven: each rule's `threads`, `mem_gb`, `runtime_min` live under
`resources:` in `config.yaml`, and `_resources()` translates them to Slurm (or SGE) keys for
the active profile. Initial values are guesses. After a run, replace them with measurements:

```bash
uv run python workflow/scripts/calibrate_resources.py --output_dir results
```

Two more per-rule conventions (why they matter is in `hello.smk` and `AGENTS.md`): the
script is declared as an `input:` so edits rerun the rule, and every rule writes a persistent
`log:` under `{output_dir}/logs/<rule>/` because scheduler logs are deleted on success.

## Running on Wynton SGE (deprecated)

> **Deprecated and unmaintained.** This path still works for pipelines already on Wynton,
> but fixes and features go to CoreHPC Slurm. `dry-run-sge` / `run-sge` print a warning.

```bash
ssh log1.wynton.ucsf.edu
cd <your clone>
uv sync
./workflow/test_pipeline.sh build --push          # optional: push custom images first
uv run ./workflow/test_pipeline.sh dry-run-sge
uv run ./workflow/test_pipeline.sh run-sge
```

Wynton defaults are baked in: `/opt/sge/wynton/common/accounting` for `qacct` status checks
(override with `SGE_ACCOUNTING`), `--bind /scratch`, and per-slot `mem_free` handling in
`workflow/profiles/sge/config.yaml`. Non-Gladstone users edit the bind paths in
`workflow/config/config_wynton.yaml.example`.

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

- **Did the run finish?** Every run writes `{output_dir}/logs/status/latest.txt`
  (`SUCCESS` / `FAILED` + timestamp). It needs no mail, network, or scheduler.
- **No email arrived.** `send_notification()` needs `mail` or `sendmail`, which CoreHPC nodes
  lack. `launch.sh` has the Slurm controller send it instead (`--mail-type=END,FAIL`).
  Details in [`../workflow/profiles/slurm/README.md`](../workflow/profiles/slurm/README.md).
- **First Apptainer run is slow.** `onstart` pulls missing `.sif` files into `containers.dir`.
  Set `containers.auto_pull: false` if you manage SIFs yourself.
- **A Slurm job sits in `PD` forever.** Read the reason in `squeue`. `(PartitionTimeLimit)`
  means `runtime_min` exceeds the partition MaxTime; `(Resources)` can mean no node has that
  much memory. Neither fails on its own. Cap `runtime_min` and `max_node_mem_gb`.
- **`Failed to initialize cache ... Disk quota exceeded`.** The uv or Apptainer cache is in
  `$HOME`. Point `UV_CACHE_DIR` / `APPTAINER_CACHEDIR` at project storage (`launch.sh` does).
- **A cheap rule wants to rebuild the whole pipeline.** An intermediate is missing, or a
  killed job left a `Forced execution` flag. `--rerun-triggers mtime` prevents neither.
  Dry-run and read the job table first; `launch.sh` guarded scopes do this automatically.
- **An edited script did not rerun its rule.** The rule is missing
  `script=script_path(...)` in its `input:`.
- **Stale lock after a killed driver.**
  `uv run snakemake --snakefile workflow/Snakefile --configfile <cfg> --unlock`.
  Prefer `scancel --signal=TERM` so it exits cleanly.
- **SGE jobs show "success" but outputs are missing** (deprecated path).
  `workflow/profiles/sge/status.sh` consults `qacct` to catch this; confirm
  `SGE_ACCOUNTING` is readable from the submission host.
