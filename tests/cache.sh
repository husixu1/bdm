#!/bin/bash
THISDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THISDIR="${THISDIR:?"THISDIR not found :("}"
cd "$THISDIR/.." || exit 1

# build named cahce of kcov image to speedup testing
docker build -t test/kcov --target=kcov -f tests/Dockerfile .
docker image prune -f
