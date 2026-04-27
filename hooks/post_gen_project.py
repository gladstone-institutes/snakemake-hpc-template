"""After generation: chmod +x shell scripts, init git, print next-steps."""
import os
import stat
import subprocess
from pathlib import Path

project_root = Path.cwd()

SCRIPT_PATHS = [
    "workflow/test_pipeline.sh",
    "workflow/profiles/sge/status.sh",
    "workflow/containers/hello/build.sh",
]

for rel in SCRIPT_PATHS:
    p = project_root / rel
    if p.exists():
        mode = p.stat().st_mode
        p.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

try:
    subprocess.run(["git", "init", "-q"], check=True, cwd=project_root)
    subprocess.run(["git", "add", "."], check=True, cwd=project_root)
    subprocess.run(
        ["git", "commit", "-q", "-m", "Initial commit from snakemake-hpc-template"],
        check=True,
        cwd=project_root,
        env={**os.environ, "GIT_COMMITTER_NAME": "{{ cookiecutter.author_name }}",
             "GIT_COMMITTER_EMAIL": "{{ cookiecutter.author_email }}",
             "GIT_AUTHOR_NAME": "{{ cookiecutter.author_name }}",
             "GIT_AUTHOR_EMAIL": "{{ cookiecutter.author_email }}"},
    )
except (subprocess.CalledProcessError, FileNotFoundError):
    pass

print()
print("=" * 60)
print("  Project {{ cookiecutter.project_slug }} generated.")
print("=" * 60)
print()
print("Next steps:")
print("  cd {{ cookiecutter.project_slug }}")
print("  uv sync")
print("  source .venv/bin/activate")
print("  ./workflow/test_pipeline.sh dry-run")
print("  ./workflow/test_pipeline.sh run")
print()
print("See README.md for Wynton SGE and Slurm instructions.")
print()
