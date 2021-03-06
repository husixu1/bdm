#!/bin/bash
if [[ -n $__DEFINED_UTILS_SH ]]; then return; fi
declare __DEFINED_UTILS_SH=1

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

# $1: prefix
# ${@:1} messages
log:__print() {
    local prefix="$1"
    shift
    local indent=""
    if [[ ${LOG_INDENT:-x} =~ ^[[:digit:]]+$ ]]; then
        for _ in $(seq "$LOG_INDENT"); do
            indent+=" "
        done
    fi

    echo -n "${indent}${prefix} "
    echo "$1"
    shift
    indent+="    "

    for line in "$@"; do
        echo "${indent}${line}"
    done
}

# env $INDENT: indent width
# $@: message, printed one per line
log:error() {
    log:__print "[1m[91mERR:[0m" "$@" >&2
}

log:warning() {
    log:__print "[1m[93mWRN:[0m" "$@" >&2
}

log:info() {
    log:__print "[1m[92mINF:[0m" "$@" >&1
}
