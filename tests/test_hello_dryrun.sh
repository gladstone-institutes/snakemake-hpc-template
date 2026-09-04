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
DRY="$(uv run ./workflow/pipeline.sh dry-run 2>&1)"
echo "$DRY" | tail -3
# The run-as-user default must reach the rule's shell command.
grep -qF -- '--user $(id -u):$(id -g) -e HOME=/workspace' <<<"$DRY" \
  || { echo "docker_run_as_user default missing from the shell command" >&2; exit 1; }

# project_root must reach the DAG: a relative output_dir resolves under it.
# Captured first: with pipefail, grep -q closing the pipe early would fail it.
ROOT="$TMPDIR_BAKE/pr"
OUT="$(uv run ./workflow/pipeline.sh dry-run --config "project_root=$ROOT" 2>&1)"
grep -q "$ROOT/.tests/integration/results/" <<<"$OUT" \
  || { echo "project_root did not resolve output_dir" >&2; exit 1; }

echo "Dry-run OK: $PROJECT_DIR"
