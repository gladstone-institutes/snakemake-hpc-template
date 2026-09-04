"""Bake the template with defaults and assert key files exist."""
from pathlib import Path

EXPECTED = [
    "README.md",
    "AGENTS.md",
    "docs/PIPELINE.md",
    "docs/containers.svg",
    "pyproject.toml",
    ".gitignore",
    ".python-version",
    "workflow/Snakefile",
    "workflow/pipeline.sh",
    "workflow/rules/common.smk",
    "workflow/rules/containers.smk",
    "workflow/rules/hello.smk",
    "workflow/launch.sh",
    "workflow/scripts/hello.sh",
    "workflow/scripts/calibrate_resources.py",
    "workflow/scripts/resolve_sifs.py",
    "workflow/scripts/config_paths.py",
    "workflow/config/config.yaml",
    "workflow/config/test_config.yaml",
    "workflow/config/test_config_apptainer.yaml",
    "workflow/config/test_config_apptainer_slurm.yaml",
    "workflow/config/config_wynton.yaml.example",
    "workflow/config/config_corehpc.yaml.example",
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
        "workflow/pipeline.sh",
        "workflow/launch.sh",
        "workflow/scripts/hello.sh",
        "workflow/profiles/sge/status.sh",
        "workflow/containers/hello/build.sh",
    ):
        path = project / rel
        assert path.exists()
        assert path.stat().st_mode & 0o111, f"{rel} not executable"


def test_template_version_is_in_sync(cookies):
    """cookiecutter.json stamps the version into generated projects; it must match pyproject."""
    import json
    import tomllib

    root = Path(__file__).resolve().parent.parent
    pyproject = tomllib.loads((root / "pyproject.toml").read_text())["project"]["version"]
    stamped = json.loads((root / "cookiecutter.json").read_text())["_template_version"]
    assert stamped == pyproject, f"cookiecutter.json _template_version {stamped} != pyproject {pyproject}"
    changelog = (root / "CHANGELOG.md").read_text()
    assert f"## [{pyproject}]" in changelog, f"CHANGELOG.md has no entry for {pyproject}"
    result = cookies.bake()
    assert result.exit_code == 0
    generated = (Path(result.project_path) / "CHANGELOG.md").read_text()
    assert f"version {pyproject}" in generated


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
