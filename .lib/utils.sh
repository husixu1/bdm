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

# $1: transaction name
newTransaction() {
#    declare -a "$1_COMMAND"
    declare -a "$1_ROLLBACK"
}

# $1 transaction name
setCurTransaction() {
#    _TRANSACTION_COMMAND=$1_COMMAND
    _TRANSACTION_ROLLBACK=$1_ROLLBACK
}

#1 transaction name
commit() {
    unset "$1_COMMAND"
    unset "$1_ROLLBACK"
    unset _TRANSACTION_ROLLBACK
}

rollback() {
    local rollbackCount=${#_TRANSACTION_ROLLBACK[@]}
    # execute the rollback stack in reverse
    for ((i=0; i<rollbackCount; ++i)); do
        local rollbackCommand
        eval "rollbackCommand=(${_TRANSACTION_ROLLBACK[$((rollbackCount-i))]})"
        $rollbackCommand
    done
}

# params before `---`: action command
# params after `---`: rollback command
action() {
    local state="command"
    local actionParamCount=0
    for param in "$@"; do
        [[ ${state} == "command" && ${param} == "---" ]] && break;
        ((++actionParamCount))
    done

    # _TRANSACTION_COMMAND+=$(printf "%q " "${@::${actionParamCount}}")
    _TRANSACTION_ROLLBACK+=$(printf "%q " "${@:$((actionParamCount+1))}")
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
