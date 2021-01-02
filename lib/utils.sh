#!/bin/bash

# $1: package name to be recognized by package manager
# $2: executable name. defaults to $1
# return: 0 if package or executable exist. 1 otherwise
# testSystemPackage() {
#     local result=1
#     local exe=${2:-$1}
#     pacman -Q "$1" >/dev/null 2>&1 && result=0
#     pacman -Qg "$1" >/dev/null 2>&1 && result=0
#     command -v "$exe" >/dev/null 2>&1 && result=0
#     return $result
# }

error() {
    echo "[1m[91mERR:[0m $*" >&2
}

warning() {
    echo "[1m[93mWRN:[0m $*" >&2
}

info() {
    echo "[1m[92mINF:[0m $*" >&1
}

debug() {
    echo "[1m[94mDBG:[0m $*" >&2
}
