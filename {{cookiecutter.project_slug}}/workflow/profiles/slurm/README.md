# Slurm profile (UCSF CoreHPC)

Targets UCSF CoreHPC (Gladstone), **validated end-to-end** with CPU and GPU jobs.
Uses `snakemake-executor-plugin-slurm`, which handles submission, polling, and
cancellation natively (no custom `status.sh`). This file is the single home for
the driver-job pattern, notifications, and every CoreHPC gotcha; the user-facing
overview is in [`../../../docs/PIPELINE.md`](../../../docs/PIPELINE.md).

## Setup

```bash
uv sync   # installs snakemake-executor-plugin-slurm (a pyproject.toml dep)
```

## Running

```bash
# Test fixtures (the hello example):
uv run ./workflow/test_pipeline.sh dry-run-slurm   # validate DAG + config
uv run ./workflow/test_pipeline.sh run-slurm       # run on the cluster (needs sbatch)

# Real samples, via a per-cluster config (copy config_corehpc.yaml.example).
# Prefer ../../launch.sh for anything long; the raw invocation is:
snakemake --snakefile workflow/Snakefile \
    --configfile workflow/config/config_corehpc.yaml \
    --profile workflow/profiles/slurm --dry-run     # drop --dry-run to run live
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

## Long runs: submit snakemake itself as a driver job

**Do not run a multi-hour snakemake from a CoreHPC login shell.** The login node
sets `KillUserProcesses=yes` with `Linger=no`, so systemd-logind reaps every
process you own when the SSH session drops — tmux included. Put the orchestrator
on a compute node instead:

```bash
./workflow/launch.sh all check     # dry-run locally, submit nothing
./workflow/launch.sh all           # pre-pull images, then submit the driver
```

`workflow/launch.sh` writes an sbatch script, submits it, and returns. The
driver submits the step jobs with `sbatch` from inside its own job, which
CoreHPC allows (munge-based, no Kerberos ticket needed). Edit its `scope_setup`
table to add the ways you actually run the pipeline; each scope declares its
`--until` rules, its images, and its walltime in one place.

Cancel a driver **gracefully** so snakemake cleans up instead of leaving a stale
lock and incomplete outputs:

```bash
scancel --signal=TERM <jobid>     # then wait; SIGKILL only if it hangs
# after a hard kill:
uv run snakemake --snakefile workflow/Snakefile --configfile <cfg> --unlock
```

## Cluster gotchas beyond GPU

Each of these cost real debugging time on CoreHPC:

- **Partition MaxTime pends forever, it does not fail.** A job asking for more
  walltime than the partition allows is accepted and then sits in `PD` with
  reason `(PartitionTimeLimit)`, indistinguishable from an ordinary queue wait.
  Check it and cap your requests: `scontrol show partition cpu | tr ' ' '\n' |
  grep -i maxtime` (CoreHPC `cpu` is `7-00:00:00`). Same shape for memory: a
  request larger than any node pends as `(Resources)` — hence
  `max_node_mem_gb` in `config.yaml`.
- **Compute nodes have no outbound internet.** Pre-pull `.sif` files on the
  login node (`./workflow/launch.sh <scope> prepull`, or
  `uv run ./workflow/test_pipeline.sh prepull <config>`) and set
  `containers.auto_pull: false` in the cluster config. Anything else that
  fetches at runtime (an R annotation hub, a model download) needs the same
  treatment: fetch to a cache on the login node and read the cache in the rule.
- **Caches must not live in `$HOME`.** CoreHPC home has a small quota, and
  `apptainer pull` fills it with image layers — after which `uv run` dies with
  `Failed to initialize cache ... Disk quota exceeded (os error 122)` before
  snakemake even starts. `launch.sh` puts `UV_CACHE_DIR` and
  `APPTAINER_CACHEDIR` on the project filesystem, and `APPTAINER_TMPDIR` on
  `/mnt/scratch/user/$USER` — the two want opposite filesystems, since TMPDIR is
  throwaway build space where pull speed is set, and the caches are persistent.
- **`--rerun-triggers mtime` is worth setting for read-only scopes**, so an
  edited script or a touched config does not invalidate finished expensive
  outputs. But it gates *change* detection only: it will not stop Snakemake from
  rebuilding a **missing** intermediate, and it does not clear a `Forced
  execution` flag left behind by a killed job. That is what `launch.sh`'s
  `guard_dag` is for — dry-run a cheap scope and refuse to submit if the DAG
  grew beyond it.
- **`--configfile` takes `nargs='+'`**, so any flag or positional target after
  it is swallowed. Put extra flags *before* `--configfile`, and prefer scoping a
  run with `--until <rule>` over trailing target paths (with
  `--resources max_concurrent_gpu_jobs=1` active, trailing positionals are
  dropped as "unrecognized arguments" and `--` is not honoured).
- **Submit a driver via a written job-script file, not an `sbatch` stdin
  heredoc.** The heredoc route has reached snakemake with a stray empty argument
  that the identical interactive command never had. `launch.sh` writes the
  script and prints the resolved argv before running.
- **`max_rss` in a `benchmark:` file sums the process tree**, so a rule that
  forks (R `future`/`mclapply`, python multiprocessing) reports well above its
  true peak. Treat it as an upper bound when calibrating.

## Notifications (no `mail` on CoreHPC)

`common.smk:send_notification()` shells out to `mail` / `sendmail`. **No CoreHPC
node has either**, and compute nodes have no outbound internet to reach an SMTP
relay — and under the driver-job pattern snakemake itself runs on a compute
node. So the config's `notification.email` alone will never deliver anything
there. Three things that do work:

**1. Let the Slurm controller send the mail.** `slurmctld` runs on the
controller, which has an MTA configured by the admins, so mail requested with
`--mail-type` is delivered even though your job could not have sent it itself.
`launch.sh` does this automatically for the driver job, using
`notification.email` from the config:

```bash
./workflow/launch.sh all                       # --mail-type=END,FAIL --mail-user=<config email>
NOTIFY_EMAIL=me@example.org ./workflow/launch.sh all
MAIL_TYPE=NONE ./workflow/launch.sh all        # opt out
```

The driver's mail reports the *orchestrator's* final state, which is the one
you want: it arrives when the whole run ends, not per step job. Confirm your
site actually has it wired before relying on it:

```bash
scontrol show config | grep -i mailprog        # expect a real binary, not (null)
sbatch --mail-type=END --mail-user=you@example.org --wrap 'sleep 5'   # then check inbox/spam
```

For a single long rule you can also add
`slurm_extra="'--mail-type=FAIL --mail-user=you@example.org'"` to its
`resources:`. Don't do it pipeline-wide — one mail per job gets loud fast.

**2. The status file, which always works.** Every run writes
`{output_dir}/logs/status/latest.txt` (plus a timestamped copy) from `onsuccess`
/ `onerror`, holding `SUCCESS` or `FAILED`, a UTC timestamp, and the same body
the email would have carried. No MTA, no network, no scheduler involved:

```bash
cat  $OUT/logs/status/latest.txt
ls -t $OUT/logs/status/ | head        # history across runs
```

**3. Poll from somewhere with internet.** If you want a push notification
(Slack, ntfy, a phone), run the poller on a machine that has network access —
your laptop or a login node — watching the status file over SSH. Don't put an
HTTPS call inside a rule: compute nodes cannot make it, and the failure lands in
the middle of your pipeline.
