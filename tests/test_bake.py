"""Bake the template with defaults and assert key files exist."""
from pathlib import Path

EXPECTED = [
    "README.md",
    "docs/PIPELINE.md",
    "pyproject.toml",
    ".gitignore",
    ".python-version",
    "workflow/Snakefile",
    "workflow/test_pipeline.sh",
    "workflow/rules/common.smk",
    "workflow/rules/hello.smk",
    "workflow/config/config.yaml",
    "workflow/config/test_config.yaml",
    "workflow/config/test_config_apptainer.yaml",
    "workflow/config/config_wynton.yaml.example",
    "workflow/config/samples.tsv",
    "workflow/config/test_samples.tsv",
    "workflow/profiles/local/config.yaml",
    "workflow/profiles/apptainer-dev/config.yaml",
    "workflow/profiles/sge/config.yaml",
    "workflow/profiles/sge/status.sh",
    "workflow/profiles/slurm/config.yaml",
    "workflow/profiles/slurm/README.md",
    "workflow/containers/hello/Dockerfile",
    "workflow/containers/hello/build.sh",
    "tests/test_smoke.py",
]


def test_bake_with_defaults(cookies):
    result = cookies.bake()
    assert result.exit_code == 0
    assert result.exception is None
    project = Path(result.project_path)
    assert project.is_dir()
    for rel in EXPECTED:
        assert (project / rel).exists(), f"missing: {rel}"


def test_scripts_are_executable(cookies):
    result = cookies.bake()
    assert result.exit_code == 0
    project = Path(result.project_path)
    for rel in (
        "workflow/test_pipeline.sh",
        "workflow/profiles/sge/status.sh",
        "workflow/containers/hello/build.sh",
    ):
        path = project / rel
        assert path.exists()
        assert path.stat().st_mode & 0o111, f"{rel} not executable"


def test_jinja_substitution_applied(cookies):
    result = cookies.bake(extra_context={
        "project_name": "Demo Pipeline",
        "author_name": "Alice",
        "author_email": "alice@example.com",
        "docker_username": "alice",
    })
    assert result.exit_code == 0
    project = Path(result.project_path)
    assert project.name == "demo-pipeline"
    pyproject = (project / "pyproject.toml").read_text()
    assert 'name = "demo-pipeline"' in pyproject
    assert "alice@example.com" in pyproject
