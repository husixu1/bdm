#!/bin/bash

# install kcov
version="$(curl --silent "https://api.github.com/repos/SimonKagstrom/kcov/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
curl -L "https://github.com/SimonKagstrom/kcov/archive/refs/tags/${version}.tar.gz" -o "${version}.tar.gz"
tar -xvzf "${version}.tar.gz"


# build kcov
pushd kcov-"${version}" || exit 1
mkdir build
pushd build || exit 1

cmake ..
make -j4
make install

popd || exit 1
popd || exit 1
