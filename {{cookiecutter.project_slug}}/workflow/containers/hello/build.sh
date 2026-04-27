#!/usr/bin/env bash
set -euo pipefail

# Docker image name. Change this (and containers.images.hello in config.yaml)
# when retargeting a different registry/account.
IMAGE="{{ cookiecutter.docker_username }}/hello"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION=$(sed -n 's/^LABEL version="\([^"]*\)"/\1/p' "${SCRIPT_DIR}/Dockerfile")
if [[ -z "${VERSION}" ]]; then
    echo "ERROR: could not extract version from Dockerfile" >&2
    exit 1
fi

TAG="${IMAGE}:${VERSION}"

PUSH=false
NO_CACHE=""
PLAIN=""
for arg in "$@"; do
    case "${arg}" in
        --push)     PUSH=true ;;
        --no-cache) NO_CACHE="--no-cache" ;;
        --plain)    PLAIN="--progress=plain" ;;
        *)
            echo "Usage: $0 [--push] [--no-cache] [--plain]" >&2
            exit 1
            ;;
    esac
done

if docker image inspect "${TAG}" &>/dev/null; then
    read -rp "Image ${TAG} already exists locally. Overwrite? [y/N] " confirm
    if [[ "${confirm}" != [yY] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Building ${TAG} ..."
docker build \
    --platform linux/amd64 \
    ${NO_CACHE} \
    ${PLAIN} \
    -t "${TAG}" \
    "${SCRIPT_DIR}"

if ${PUSH}; then
    echo "Pushing ${TAG} ..."
    docker push "${TAG}"
fi

echo "Done."
