#!/bin/bash

export LOCAL_CONFIG_DIR="${XDG_CONFIG_HOME:-"$HOME/.config"}"

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

# installSystemPackages() {
#     sudo pacman -S --needed --noconfirm "$@"
# }

# start new transaction
transaction() {
    [[ -z ${_ROLLBACKS+x} ]] || {
        error "Already in transaction"
        return 1
    }
    _ROLLBACKS=("true")
}

#1 transaction name
commit() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Commit when not in transaction"
        return 1
    }
    unset _ROLLBACKS
}

rollback() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Rollback when not in transaction"
        return 1
    }

    local rollbackCount=${#_ROLLBACKS[@]}
    # execute the rollback stack in reverse
    for ((i=0; i<rollbackCount; ++i)); do
        local -a rollbackCommand
        eval "rollbackCommand=(${_ROLLBACKS[$((rollbackCount-i-1))]})"
        "${rollbackCommand[@]}"
    done
    unset _ROLLBACKS
}

# params before `---`: action command
# params after `---`: rollback command
action() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Try to perform action when not in transaction"
        return 1
    }

    local actionParamCount=1
    for param in "$@"; do
        [[ ${param} == "---" ]] && break;
        ((++actionParamCount))
    done

    # Add rollback to rollback list
    _ROLLBACKS+=("$(printf "%q " "${@:$((actionParamCount+1))}")")

    # perform action
    "${@:1:$((actionParamCount-1))}"
}


# $1: source file/directory
# $2: target file/directory (a symlink)
# return: 0 if installed successfully. 1 otherwise
#
# If `target` already exists and it's not a link to `source`,
# installation will fail and return 1
# If `target` already exists and it is a link to `source`,
# nothing happens and 0 is returned
installSymLink() {
    # If target file is a symlink
    [[ -L "$2" ]] && {
        # if this symlink points to source file, return 0
        [[ $1 -ef $2 ]] && return 0
        # otherwise return 1
        return 1
    }

    # Otherwise if target file exists, return 1
    [[ -e "$2" ]] && return 1

    # Otherwise try link the source to target
    ln -s "$1" "$2"
}

# $1: source file/directory
# $2: target file/directory (a symlink)
# return: 0 if `target` is removed successfully, 1 otherwise
#
# If `target` is not a symlink to `source` or cannot be removed, 1 is returned
# If `target` does not exists, nothing happens and 0 is returned
uninstallSymLink() {
    # target does not exists
    [[ -e "$2" ]] && return 0
    # target is not a symlink or source and target is not the same file
    [[ ! -L "$2" || ! $1 -ef $2 ]] && return 1

    # try unlink target
    unlink "$2"
}

error() {
    echo "BOOTSTRAP-ERR: " "$@" >/dev/stderr
}

warning() {
    echo "BOOTSTRAP-WRN: " "$@" >/dev/stderr
}

# From https://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script
distro() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        ...
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        ...
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    [[ ${OS} =~ ^Arch.* ]] && echo "arch"
    [[ ${OS} =~ ^Debian ]] && echo "debian${VER}"
    # Add more os supports here
}
