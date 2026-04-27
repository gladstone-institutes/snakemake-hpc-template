"""Smoke tests that run without Docker or a Snakemake workflow."""
from pathlib import Path


def test_required_files_exist():
    root = Path(__file__).resolve().parent.parent
    for rel in (
        "workflow/Snakefile",
        "workflow/rules/common.smk",
        "workflow/rules/hello.smk",
        "workflow/config/test_config.yaml",
        "workflow/config/test_samples.tsv",
        "workflow/profiles/sge/config.yaml",
        "workflow/profiles/sge/status.sh",
        "workflow/test_pipeline.sh",
    ):
        assert (root / rel).exists(), f"missing: {rel}"


def test_test_samples_has_rows():
    root = Path(__file__).resolve().parent.parent
    rows = (root / "workflow/config/test_samples.tsv").read_text().strip().splitlines()
    assert len(rows) >= 2  # header + at least one sample
