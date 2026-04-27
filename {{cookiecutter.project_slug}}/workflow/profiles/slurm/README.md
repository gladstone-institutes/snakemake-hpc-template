# Slurm profile (experimental)

This profile is a stub for UCSF CoreHPC. It has **not** been validated end-to-end. The Wynton SGE profile (`workflow/profiles/sge/`) is the supported HPC path.

## Setup

```bash
uv add snakemake-executor-plugin-slurm
```

## Required edits in `config.yaml`

1. `slurm_account` — billing account string.
2. `slurm_partition` — queue/partition name.
3. `apptainer-args` — confirm the right bind paths for your compute nodes (CoreHPC uses `$TMPDIR`; some clusters expose `/scratch`).

## Per-rule tuning

Add blocks under `set-resources:` as needed. Slurm resource keys differ from SGE:

| SGE | Slurm |
|---|---|
| `mem_free` (per-slot) | `mem_mb` (total) |
| `scratch` | (site-dependent — sometimes `disk_mb`) |
| `h_rt` (HH:MM:SS) | `runtime` (minutes) |
| `-pe smp {threads}` | `cpus_per_task: {threads}` |

## Running

```bash
snakemake --snakefile workflow/Snakefile \
    --configfile workflow/config/config.yaml \
    --profile workflow/profiles/slurm
```

## Feedback wanted

When you run this against CoreHPC, please open a PR upstreaming what worked — the goal is for this profile to become as load-bearing as the SGE one.
