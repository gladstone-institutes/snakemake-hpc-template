# common.smk - Shared helpers for {{ cookiecutter.project_name }}.
#
# Load-bearing pieces:
#   - PIPELINE_VERSION: read from pyproject.toml; injected into notifications.
#   - SHADOW_MODE: 'shallow' on HPC (Apptainer), None under local Docker.
#   - USE_APPTAINER: true on HPC, drives the onstart SIF auto-pull.
#   - load_samples: generic TSV loader; required columns sample_id, description.
#   - docker_run / get_container_path: dual-mode container entry points.
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
    string works unchanged under Apptainer (where Snakemake's `container:`
    directive handles execution).
    """
    if config.get("execution", {}).get("use_docker", False):
        image_path = get_docker_image(image_name).replace("docker://", "")
        extra = f" {extra_args}" if extra_args else ""
        bind_mounts = " ".join(
            f"-v '{m}:{m}'" for m in config.get("execution", {}).get("docker_bind_mounts", [])
        )
        if bind_mounts:
            bind_mounts = f" {bind_mounts}"
        return f"docker run --rm{extra} -v $(pwd):/workspace{bind_mounts} -w /workspace {image_path}"
    return ""


def get_all_samples():
    """List of sample IDs."""
    return list(samples.index)


# Load samples at module initialization.
samples = load_samples(config["samples"])
