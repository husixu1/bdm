#!/bin/bash

set -euo pipefail

DOTFILES_ROOT=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd
)
export DOTFILES_ROOT

# shellcheck source=./.lib/utils.sh
source "${DOTFILES_ROOT}/.lib/utils.sh"


#    # At least `sudo` is needed
#    command -v sudo >/dev/null 2>&1 || {
#        error "the 'sudo' program is needed for running this script"
#        exit 1
#    }
#
#    # Require root previliges
#    sudo -v
#
#    # keep sudo credential cache up-to-date
#    while true; do
#        sudo -n true
#        sleep 60
#        kill -0 "$$" || exit
#    done 2>/dev/null &
#

dispatchCommand (){
    cmd=$1
    shift

    # Scan for all `bootstrap.sh` and run them
    packages=("$@")

    [[ $1 == 'all' ]] && mapfile -t packages < <(ls)

    for package in "${packages[@]}"; do
        [ -f "$DOTFILES_ROOT/$package/bootstrap.sh" ] && {
            (# run in subshell. exit when any error happens
                set -e
                # shellcheck source=./vim/bootstrap.sh
                source "$DOTFILES_ROOT/$package/bootstrap.sh"
                type "$cmd" >/dev/null 2>&1 && $cmd
            )
            # We can't use `(set -e;cmd1;cmd2;...;) || warning ...` or if-else here.
            # see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
            # shellcheck disable=SC2181
            [[ $? == 0 ]] || warning "Failed installing $package"
        }
    done
}

dispatchCommand "$@"
