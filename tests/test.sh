#!/bin/bash

# This is the main test script.
# It Builds the docker image, then run the tests in docker
# and stores the results in ../artifacts

THISDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THISDIR="${THISDIR:?"THISDIR not found :("}"
cd "$THISDIR/.." || exit 1

# check if docker daemon started
command -v docker >/dev/null 2>&1 || {
    echo "Docker not installed" >&2
    exit 1
}

docker ps -q >/dev/null 2>&1 || {
    echo "Docker daemon not started"
    exit 1
}

# build docker images
set -eo pipefail
docker build -t test/dotfiles -f tests/Dockerfile .
docker image prune -f

# clean artifacts directory
if [[ -d artifacts ]]; then rm -rf artifacts; fi
mkdir artifacts

# run tests with docker
docker run --rm \
    -t \
    -v"$(realpath ./artifacts)":/artifacts \
    -u user:user \
    test/dotfiles:latest
