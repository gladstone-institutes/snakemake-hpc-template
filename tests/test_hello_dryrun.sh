#!/usr/bin/env bash
# Bake the template into a tmpdir, sync deps, and run `dry-run`.
# Exits 0 on success. Requires: cookiecutter, uv on PATH.

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_BAKE="$(mktemp -d)"
trap "rm -rf $TMPDIR_BAKE" EXIT

cookiecutter --no-input --output-dir "$TMPDIR_BAKE" "$TEMPLATE_DIR"

PROJECT_DIR="$TMPDIR_BAKE/my-snakemake-pipeline"
cd "$PROJECT_DIR"

uv sync
uv run ./workflow/test_pipeline.sh dry-run

echo "Dry-run OK: $PROJECT_DIR"
