#!/bin/bash

#shellcheck source=./transaction.sh
source "$(dirname "${BASH_SOURCE[0]}")"/transaction.sh
#shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")"/utils.sh

# $1: source file/directory
# $2: target file/directory (a symlink)
# $3 (optional): `asroot' means install symlink as root
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

    if [[ $3 == asroot ]]; then
        sudo ln -s "$1" "$2"
    else
        # Otherwise try link the source to target
        ln -s "$1" "$2"
    fi
}

# $1: source file/directory
# $2: target file/directory (a symlink)
# $3 (optional): `asroot' means remove symlink as root
# return: 0 if `target` is removed successfully, 1 otherwise
#
# If `target` is not a symlink to `source` or cannot be removed, 1 is returned
# If `target` does not exists, nothing happens and 0 is returned
removeSymLink() {
    # target does not exists
    [[ -e "$2" ]] || return 0
    # target is not a symlink or source and target is not the same file
    [[ -L "$2" && $1 -ef $2 ]] || {
        error "Link $2 is not managed by this repo"
        return 1
    }

    if [[ $3 == asroot ]]; then
        sudo unlink "$2"
    else
        # try unlink target
        unlink "$2"
    fi
}

# $1: source file/directory
# $2: target file/directory (a symlink)
# $3 (optional): `asroot' means remove symlink as root
#
# This function must be run in a transaction
# insall symlink, otherwise rollback
transactionInstallSymlink() {
    action installSymLink "$1" "$2" "$3" --- removeSymLink "$1" "$2" "$3"
}

# $1: source file/directory
# $2: target file/directory (a symlink)
# $3 (optional): `asroot' means remove symlink as root
#
# This function must be run in a transaction
# insall symlink, otherwise rollback
transactionRemoveSymlink() {
    # target does not exists
    [[ -e "$2" ]] || return 0
    # target is not a symlink or source and target is not the same file
    [[ -L "$2" && $1 -ef $2 ]] || {
        error "Link $2 is not managed by this repo"
        return 1
    }
    action removeSymLink "$1" "$2" "$3" --- installSymLink "$1" "$2" "$3"
}
