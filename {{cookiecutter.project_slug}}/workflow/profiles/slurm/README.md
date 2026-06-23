# Slurm profile (UCSF CoreHPC)

This profile targets UCSF CoreHPC (Gladstone) and is **validated end-to-end**
with CPU and GPU jobs. It uses the `snakemake-executor-plugin-slurm` plugin,
which handles job submission, status polling, and cancellation natively, so it
needs no custom `status.sh` like the SGE profile.

## Setup

```bash
uv sync   # installs snakemake-executor-plugin-slurm (a pyproject.toml dep)
```

## Running

```bash
# Test fixtures (the hello example):
uv run ./workflow/test_pipeline.sh dry-run-slurm   # validate DAG + config
uv run ./workflow/test_pipeline.sh run-slurm       # run on the cluster (needs sbatch)

# Real samples, via a per-cluster config (copy config_corehpc.yaml.example):
snakemake --snakefile workflow/Snakefile \
    --configfile workflow/config/config_corehpc.yaml \
    --profile workflow/profiles/slurm --dry-run     # confirm DAG first
snakemake --snakefile workflow/Snakefile \
    --configfile workflow/config/config_corehpc.yaml \
    --profile workflow/profiles/slurm               # run live
```

The Slurm account/partition defaults (`hpc_core` / `cpu`) live in this
directory's `config.yaml`. Change them for other Slurm sites.

## Resources

Per-rule resources are **not** set here; they live in `config["resources"]`
(`workflow/config/config.yaml`) as canonical `threads` / `mem_gb` /
`runtime_min`, and `common.smk:_resources()` translates them to Slurm keys at
parse time:

| SGE | Slurm |
|---|---|
| `mem_free` (per-slot) | `mem_mb` (total) |
| `scratch` | (not used; Slurm manages tmp via `$TMPDIR`) |
| `h_rt` (HH:MM:SS) | `runtime` (minutes) |
| `-pe smp {threads}` | `cpus_per_task` (auto-mapped from the rule's `threads:`) |
| `-q gpu.q -l gpu_mem=...` | `--partition=<gpu> --gres=<gres>` |

Use this profile's commented `set-resources:` block only for on-cluster tuning
that must differ from the config defaults.

## GPU routing

A rule requests a GPU by passing `gpu=True` to `apptainer_run()` **and**
`_resources()` (see the example in `workflow/rules/hello.smk`). When it does,
`_resources()` adds, for Slurm:

- `slurm_partition` — overridden from the default `cpu` to the GPU partition
- `gres` — rendered to `--gres=gpu:<model>:<count>`
- `max_concurrent_gpu_jobs: 1` — counted against this profile's global cap

Both partition and gres come from the config `gpu:` block (defaults target
CoreHPC L40s nodes):

```yaml
gpu:
  slurm_partition: "small_gpu"
  slurm_gres: "gpu:nvidia_l40s:1"
```

Things this profile gets right (each cost real debugging on CoreHPC):

- **`gres`, not `slurm_extra`.** Recent plugin versions forbid `--gres` inside
  `slurm_extra`; using it makes the job silently fail to submit and **deadlocks**
  the scheduler (the `max_concurrent_gpu_jobs` slot never releases). We emit the
  plugin's native `gres` resource instead.
- **`scheduler: greedy`.** The default ILP scheduler stalls at "Selecting jobs
  to execute…" when the custom `max_concurrent_gpu_jobs` resource is present.
- **`max_concurrent_gpu_jobs=1`** matches CoreHPC's per-user GPU limit; raise it
  with `--resources max_concurrent_gpu_jobs=N` if you have a higher allowance.
- **`--nv` + cgroups.** `apptainer_run(gpu=True)` adds `--nv`; Slurm sets
  `CUDA_VISIBLE_DEVICES` itself via cgroups, and apptainer inherits the caller's
  env (no `--cleanenv`), so torch picks it up automatically — we do **not**
  inject a `--env` override (unlike the SGE path, which maps `$SGE_GPU`).
- **Bind `/mnt/scratch`.** GPU jobs need it for tempfiles, the matplotlib font
  cache, and pyarrow spill (set in `containers.bind_paths`).

GPU utilization can be logged per job with `gpu_sampler_prefix()` (writes
`gpu_usage_<rule>_<jobid>.csv`); see the commented example in `hello.smk`.
