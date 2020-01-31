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
    echo "BOOTSTRAP-ERR: " "$@" >&2
}

warning() {
    echo "BOOTSTRAP-WRN: " "$@" >&2
}

info() {
    echo "BOOTSTRAP-INF: " "$@" >&1
}
