#!/bin/bash
# Test-harness CLI for {{ cookiecutter.project_name }}.
#
# Requires snakemake on $PATH. Recommended: prefix with `uv run` so the
# project's .venv is used without a separate `source .venv/bin/activate`:
#
#   uv sync                                      # once, after a fresh clone
#   uv run ./workflow/test_pipeline.sh dry-run
#
# Usage:
#   ./workflow/test_pipeline.sh [command] [extra snakemake args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_CONFIG="workflow/config/test_config.yaml"
LOCAL_PROFILE="workflow/profiles/local"
APPTAINER_CONFIG="workflow/config/test_config_apptainer.yaml"
APPTAINER_DEV_PROFILE="workflow/profiles/apptainer-dev"
SGE_PROFILE="workflow/profiles/sge"
CONTAINERS_DIR="workflow/containers"

cd "$PROJECT_DIR"

sm() {
    snakemake --snakefile workflow/Snakefile "$@"
}

banner() {
    echo "  snakemake $(snakemake --version)"
    echo "  config:  $1"
    echo "  profile: $2"
    echo ""
}

require() {
    command -v "$1" &>/dev/null && return
    echo "Error: $1 not found." >&2
    [[ $# -ge 2 ]] && echo "$2" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./workflow/test_pipeline.sh [command] [extra snakemake args...]

Commands:
  dry-run              Snakemake dry-run (default)
  run                  Execute the pipeline (local Docker)
  run-apptainer        Execute the pipeline (local Apptainer)
  dry-run-sge          Dry-run with SGE cluster profile
  run-sge              Execute the pipeline (SGE cluster)
  build [image] [flags] Build every Dockerfile under workflow/containers/
                          (optionally only <image>); flags like --push and
                          --no-cache forward to each build.sh.
  dag                  Generate DAG visualization
  lint                 Lint Snakemake files
  pytest               Run Python unit tests (tests/)
  list-samples         List configured samples
  clean                Remove test output directory

Extra arguments are forwarded to snakemake.
Example: ./workflow/test_pipeline.sh run --forceall
EOF
}

cmd="${1:-dry-run}"
shift || true

case "$cmd" in
    dry-run|run|run-apptainer|dry-run-sge|run-sge|dag|lint|list-samples)
        require snakemake "Run 'uv sync && source .venv/bin/activate' first."
        ;;
esac

case "$cmd" in
    dry-run)
        echo "Running Snakemake dry-run with test config..."
        sm --configfile "$TEST_CONFIG" --dry-run --printshellcmds "$@"
        ;;

    run)
        echo "Running pipeline with test config..."
        banner "$TEST_CONFIG" "$LOCAL_PROFILE"
        sm --configfile "$TEST_CONFIG" --profile "$LOCAL_PROFILE" "$@"
        ;;

    run-apptainer)
        require apptainer
        echo "Running pipeline with Apptainer containers..."
        banner "$TEST_CONFIG + $APPTAINER_CONFIG" "$APPTAINER_DEV_PROFILE --sdm apptainer"
        sm --configfile "$TEST_CONFIG" "$APPTAINER_CONFIG" \
            --profile "$APPTAINER_DEV_PROFILE" --sdm apptainer "$@"
        ;;

    dry-run-sge)
        echo "Dry-run with SGE profile (validates DAG + cluster config)..."
        sm --configfile "$TEST_CONFIG" "$APPTAINER_CONFIG" \
            --profile "$SGE_PROFILE" --dry-run --printshellcmds "$@"
        ;;

    run-sge)
        require qsub "Must run on an SGE cluster."
        echo "Running pipeline on SGE cluster..."
        banner "$TEST_CONFIG + $APPTAINER_CONFIG" "$SGE_PROFILE"
        # Log directories are created per-rule by the profile's submit-cmd.
        mkdir -p logs
        sm --configfile "$TEST_CONFIG" "$APPTAINER_CONFIG" \
            --profile "$SGE_PROFILE" "$@"
        ;;

    build)
        filter=""
        if [[ $# -gt 0 && ! "${1:-}" =~ ^-- ]]; then
            filter="$1"
            shift
        fi
        if ! compgen -G "$CONTAINERS_DIR/*/" >/dev/null; then
            echo "No subdirectories found under $CONTAINERS_DIR/." >&2
            exit 1
        fi
        any_built=false
        any_found=false
        for dir in "$CONTAINERS_DIR"/*/; do
            name=$(basename "$dir")
            [[ -n "$filter" && "$name" != "$filter" ]] && continue
            any_found=true
            if [[ -x "$dir/build.sh" ]]; then
                echo "=== Building $name ==="
                ( cd "$dir" && ./build.sh "$@" )
                any_built=true
            else
                echo "Skipping $name (no executable build.sh)" >&2
            fi
        done
        if [[ -n "$filter" && $any_found == false ]]; then
            echo "No container matched filter: $filter" >&2
            exit 1
        fi
        if [[ $any_built == false ]]; then
            echo "No containers built." >&2
            exit 1
        fi
        ;;

    dag)
        mkdir -p workflow/test
        echo "Generating rule-level graph..."
        sm --configfile "$TEST_CONFIG" --rulegraph | dot -Tpng > workflow/test/dag.png
        echo "Rule graph saved to workflow/test/dag.png"
        ;;

    lint)
        echo "Linting Snakemake files..."
        sm --configfile "$TEST_CONFIG" --lint "$@"
        ;;

    pytest)
        echo "Running unit tests..."
        python -m pytest tests/ "$@"
        ;;

    list-samples)
        echo "Listing configured samples..."
        sm --configfile "$TEST_CONFIG" list_samples
        ;;

    clean)
        OUTPUT_DIR=$(python -c "import yaml; print(yaml.safe_load(open('$TEST_CONFIG'))['output_dir'])")
        echo "Removing test output directory: $OUTPUT_DIR"
        read -rp "Continue? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$OUTPUT_DIR"
            echo "Cleaned."
        else
            echo "Aborted."
        fi
        ;;

    *)
        usage
        exit 1
        ;;
esac

echo "Done!"
