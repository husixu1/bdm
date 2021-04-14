#!/bin/bash
# this file should be run as user:user

THISDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THISDIR="${THISDIR:?"THISDIR not found :("}"
cd "$THISDIR" || exit 1

# build & install
pushd .. || exit 1
./configure && make && sudo make install
popd || exit 1

# files to run
declare -a test_files=(test_*.sh)

# test
echo "--> Running tests ... "
for test_file in "${test_files[@]}"; do
    bash_unit "$test_file"
done

# coverage report.
# needs to bind mount a host dir to /artifacts when running docker container
[[ -d /artifacts ]] && {
    echo "--> Generating coverage reports ... "
    coverage_dirs=()
    for test_file in "${test_files[@]}"; do
        coverage_dir=/artifacts/coverage_"$test_file"
        coverage_dirs+=("$coverage_dir")

        # generate coverage report
        kcov --exit-first-process \
            --include-path=/usr/local \
            --exclude-pattern=bash_unit,templates/ \
            "$coverage_dir" \
            bash_unit "$test_file"
    done

    # merge all coverage reports
    kcov --merge /artifacts/coverage "${coverage_dirs[@]}"
}
