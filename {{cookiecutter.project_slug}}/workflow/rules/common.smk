# common.smk - Shared helpers for {{ cookiecutter.project_name }}.
#
# Load-bearing pieces:
#   - PIPELINE_VERSION: read from pyproject.toml; injected into notifications.
#   - SHADOW_MODE: 'shallow' on HPC (Apptainer), None under local Docker.
#   - USE_APPTAINER: true on HPC, drives the onstart SIF auto-pull.
#   - load_samples: generic TSV loader; required columns sample_id, description.
#   - docker_run / apptainer_run: dual-mode container entry points. Every rule
#     prepends BOTH to its shell; exactly one expands to a prefix per run mode
#     (the other is ""). Snakemake's `container:` directive is NOT used.
#   - _resources / _threads: translate canonical config["resources"][rule]
#     (mem_gb / runtime_min / threads) to scheduler-specific keys per profile.
#   - gpu_sampler_prefix: optional nvidia-smi utilization logger for GPU rules.
#   - send_notification: opt-in email via mail/sendmail when configured.

import os as _os
import sys
import tomllib
from pathlib import Path

import pandas as pd

with open(Path(workflow.basedir).parent / "pyproject.toml", "rb") as _f:
    PIPELINE_VERSION = tomllib.load(_f)["project"]["version"]

SHADOW_MODE = None if config.get("execution", {}).get("use_docker", False) else "shallow"
USE_APPTAINER = config.get("execution", {}).get("use_apptainer", False)
NOTIFICATION_EMAIL = config.get("notification", {}).get("email", None)

# Bind extra paths into Apptainer containers (shared filesystems outside $PWD).
_bind_paths = config.get("containers", {}).get("bind_paths", [])
if _bind_paths:
    _extra = ",".join(_bind_paths)
    _existing = _os.environ.get("APPTAINER_BIND", "")
    _os.environ["APPTAINER_BIND"] = f"{_existing},{_extra}" if _existing else _extra
    _os.environ["SINGULARITY_BIND"] = _os.environ["APPTAINER_BIND"]


def send_notification(subject, body=""):
    """Email notification if configured and mail/sendmail is available."""
    if not NOTIFICATION_EMAIL:
        return
    import shutil, subprocess
    mail_cmd = shutil.which("mail") or shutil.which("sendmail")
    if not mail_cmd:
        print("Note: notification email configured but no mail command found.", file=sys.stderr)
        return
    try:
        if "sendmail" in mail_cmd:
            msg = f"Subject: {subject}\nTo: {NOTIFICATION_EMAIL}\n\n{body}"
            proc = subprocess.run(
                [mail_cmd, "-t", NOTIFICATION_EMAIL],
                input=msg, text=True, timeout=30,
            )
        else:
            proc = subprocess.run(
                [mail_cmd, "-s", subject, NOTIFICATION_EMAIL],
                input=body or " ", text=True, timeout=30,
            )
        if proc.returncode != 0:
            print(f"Warning: mail command exited with code {proc.returncode}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: failed to send notification email: {e}", file=sys.stderr)


def load_samples(samples_file):
    """Load sample metadata from TSV. Requires columns: sample_id, description."""
    df = pd.read_csv(samples_file, sep="\t", comment="#")
    for required in ("sample_id", "description"):
        if required not in df.columns:
            raise ValueError(f"samples TSV is missing required column: {required!r}")
    dup = df["sample_id"][df["sample_id"].duplicated()].tolist()
    if dup:
        raise ValueError(f"Duplicate sample_id rows in samples TSV: {dup}")
    return df.set_index("sample_id", drop=False)


def get_docker_image(image_name):
    """Return the fully-qualified Docker URI for an image by config key."""
    image_config = config["containers"]["images"][image_name]
    user = image_config["user"]
    name = image_config["name"]
    tag = image_config["tag"]
    return f"docker://{user}/{name}:{tag}"


def get_apptainer_path(image_name):
    """Return the local .sif path for an image (used on HPC with Apptainer)."""
    container_dir = config["containers"]["dir"]
    image_config = config["containers"]["images"][image_name]
    name = image_config["name"]
    tag = image_config["tag"]
    return f"{container_dir}/{name}_{tag}.sif"


def get_container_path(image_name, use_apptainer=False):
    """Route to Apptainer .sif or Docker URI depending on execution mode."""
    if use_apptainer:
        return get_apptainer_path(image_name)
    return get_docker_image(image_name)


def docker_run(image_name, extra_args=""):
    """Return a 'docker run' command prefix when running in local Docker mode.

    Returns an empty string when not in Docker mode so the same rule shell
    string works in any of the three execution modes (Docker, Apptainer, host).
    `apptainer_run` is the symmetric helper for Apptainer mode.
    """
    if config.get("execution", {}).get("use_docker", False):
        image_path = get_docker_image(image_name).replace("docker://", "")
        extra = f" {extra_args}" if extra_args else ""
        bind_mounts = " ".join(
            f"-v '{m}:{m}'" for m in config.get("execution", {}).get("docker_bind_mounts", [])
        )
        if bind_mounts:
            bind_mounts = f" {bind_mounts}"
        # --entrypoint='' clears any image ENTRYPOINT so the rule's shell
        # command runs verbatim.
        return f"docker run --rm{extra} --entrypoint='' -v $(pwd):/workspace{bind_mounts} -w /workspace {image_path}"
    return ""


def apptainer_run(image_name, gpu=False):
    """Return an 'apptainer exec ... <sif>' prefix when in apptainer mode, else ''.

    Mirrors `docker_run`: when use_apptainer is true the rule shell starts with
    this prefix, so per-rule flags (--nv for GPU rules, custom binds) are
    explicit and config-driven. Snakemake's `container:` directive is NOT used
    in either mode -- both Docker and Apptainer go through these helpers.

    `$(pwd)` is bash-expanded at rule-execution time; mirrors what snakemake's
    `--home` injection used to do when we relied on `container:`.
    """
    if not USE_APPTAINER:
        return ""
    sif = get_apptainer_path(image_name)
    args = ["--home $(pwd)"]
    for p in config.get("containers", {}).get("bind_paths", []):
        args.append(f"--bind {p}")
    if gpu:
        args.append("--nv")
        # GPU device routing depends on the scheduler. The active profile sets
        # config["scheduler"]; we branch:
        #   - sge: SGE assigns one GPU per gpu.q job and only sets $SGE_GPU.
        #     Map it manually to CUDA_VISIBLE_DEVICES. The :? form makes bash
        #     exit if $SGE_GPU is unset (e.g. running outside SGE without
        #     a manual override) instead of silently grabbing device 0.
        #   - slurm: Slurm sets CUDA_VISIBLE_DEVICES itself via cgroups when
        #     --gres=gpu:N is requested. Apptainer inherits the caller's env
        #     (we do NOT use --cleanenv) so torch picks it up automatically.
        #     Adding our own --env would override Slurm's value, which is wrong.
        #   - other / unset: no override; rely on the caller's env. Useful for
        #     ad-hoc runs where the user has set CUDA_VISIBLE_DEVICES themselves.
        scheduler = config.get("scheduler")
        if scheduler == "sge":
            args.append(
                '--env CUDA_VISIBLE_DEVICES=${SGE_GPU:?must_be_set_for_GPU_runs_'
                'submit_on_gpu.q_or_set_manually}'
            )
    return "apptainer exec " + " ".join(args) + f" {sif}"


def gpu_sampler_prefix(out_dir, rule_name, gpu):
    """Shell prefix that background-samples nvidia-smi for the life of the rule,
    killing it on shell exit. Empty string unless `gpu` (CPU rules/hosts untouched).

    Mirrors docker_run/apptainer_run: prepended to the rule shell so the same shell
    string works in any execution mode. Writes
    {out_dir}/gpu_usage_{rule_name}_<jobid>.csv, where <jobid> is the scheduler job
    id resolved at runtime (Slurm, then SGE, then 'local'), so resubmissions never
    clobber prior samples and each file ties back to a job for sacct/log lookups.

    nvidia-smi runs on the host (placed before the container prefix); on Slurm the
    job cgroup scopes it to the allocated GPU. Guarded by `command -v` so a node
    without nvidia-smi degrades to no-CSV rather than failing the rule. The EXIT
    trap preserves the rule's exit code, so the sampler can't mask a failure.
    """
    if not gpu:
        return ""
    interval = int(config.get("gpu", {}).get("sampler_interval_s", 5))
    fields = (
        "timestamp,index,utilization.gpu,utilization.memory,"
        "memory.used,memory.total"
    )
    logfile = (
        f"{out_dir}/gpu_usage_{rule_name}_"
        "${SLURM_JOB_ID:-${JOB_ID:-local}}.csv"
    )
    return (
        f"mkdir -p {out_dir}; "
        f"if command -v nvidia-smi >/dev/null 2>&1; then "
        f"nvidia-smi --query-gpu={fields} --format=csv -l {interval} -f {logfile} & "
        f"_GPU_SMI_PID=$!; trap 'kill $_GPU_SMI_PID 2>/dev/null || true' EXIT; fi; "
    )


def get_all_samples():
    """List of sample IDs."""
    return list(samples.index)


def _threads(rule_name):
    """Per-rule thread count from config['resources'][rule]."""
    return int(config["resources"][rule_name]["threads"])


def _resources(rule_name, gpu=False):
    """Translate canonical resource fields to scheduler-specific keys.

    Reads ``config["resources"][rule_name]``:
      - threads:     int
      - mem_gb:      total host RAM in GB (helper handles per-slot conversion
                     for SGE; passed through as total mem_mb for Slurm)
      - scratch_gb:  optional int (SGE only; Slurm has no portable equivalent)
      - runtime_min: total runtime in minutes

    Active scheduler from ``config["scheduler"]`` (set by the profile):
      - "sge":   mem_free (per-slot), scratch, h_rt (HH:MM:SS), gpu (0/1)
      - "slurm": mem_mb (total), runtime (minutes), gres for --gres (GPU)
      - else:    no scheduler keys emitted (host/local mode, etc.)
    """
    spec = config["resources"][rule_name]
    threads = int(spec["threads"])
    mem_gb = float(spec["mem_gb"])
    runtime_min = int(spec["runtime_min"])
    scratch_gb = spec.get("scratch_gb")

    scheduler = config.get("scheduler")
    out = {}
    if scheduler == "sge":
        per_slot = mem_gb / max(threads, 1)
        out["mem_free"] = f"{per_slot:g}G"
        if scratch_gb is not None:
            out["scratch"] = f"{int(scratch_gb)}G"
        h, m = divmod(runtime_min, 60)
        out["h_rt"] = f"{h:02d}:{m:02d}:00"
        out["gpu"] = 1 if gpu else 0
    elif scheduler == "slurm":
        out["mem_mb"] = int(mem_gb * 1024)
        out["runtime"] = runtime_min
        # snakemake-slurm auto-maps the rule's `threads:` directive to
        # --cpus-per-task; no need to emit cpus_per_task here.
        if gpu:
            gpu_partition = config.get("gpu", {}).get("slurm_partition", "small_gpu")
            gpu_gres = config.get("gpu", {}).get("slurm_gres", "gpu:nvidia_l40s:1")
            out["slurm_partition"] = gpu_partition
            # Use the plugin's native `gres` resource, NOT slurm_extra. Recent
            # snakemake-executor-plugin-slurm versions forbid `--gres` inside
            # slurm_extra (validation.py forbidden-options list); the resulting
            # WorkflowError is raised in run_job on a submission worker thread,
            # where it is swallowed by the ThreadPoolExecutor future -- the job
            # never submits, its max_concurrent_gpu_jobs slot is never released,
            # and the scheduler hangs forever on "Waiting for running jobs". The
            # `gres` resource is rendered to `--gres=<value>` by set_gres_string.
            out["gres"] = gpu_gres
            # Custom resource counter; the Slurm profile sets a global
            # `max_concurrent_gpu_jobs` cap matching the cluster's per-user
            # GPU limit (CoreHPC small_gpu = 1 running GPU job). Snakemake
            # will only submit this many GPU jobs concurrently. Override at
            # the CLI with `--resources max_concurrent_gpu_jobs=N` if you
            # have a higher allowance.
            out["max_concurrent_gpu_jobs"] = 1
    # else: host/local mode / unknown scheduler -- let snakemake's defaults apply.
    return out


# Load samples at module initialization.
samples = load_samples(config["samples"])
