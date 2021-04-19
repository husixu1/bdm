#!/bin/bash
# this file should be run as user:user

THISDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THISDIR="${THISDIR:?"THISDIR not found :("}"
cd "$THISDIR" || exit 1

pushd /home/user || exit 1
# first make the distribute package as an artifact
[[ -d /artifacts ]] && {
    sudo chown user:user /artifacts
    cp bdm-*.tar.gz /artifacts
}

# extract & build & install
tar -xvzf bdm-*.tar.gz
rm bdm-*.tar.gz
pushd bdm-* || exit 1
./configure && make && sudo make install
popd || exit 1
popd || exit 1

# files to run
declare -a test_files=(test_*.sh)

# test
echo "--> Running tests ... "
all_test_passed=true
for test_file in "${test_files[@]}"; do
    bash_unit "$test_file"
    test $? -eq 0 || all_test_passed=false
done

$all_test_passed || {
    echo "--> Tests failed. Not generating coverage reports."
    exit 1
}

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
