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

install() {
    # Scan for all `bootstrap.sh` and run them
    alldirs=("$@")
    [[ $1 == 'all' ]] && mapfile -t alldirs < <(ls)

    for dir in "${alldirs[@]}"; do
        [ -f "$dir/bootstrap.sh" ] && {
            (# run in subshell. exit when any error happens
                set -e
                # shellcheck source=./vim/bootstrap.sh
                source "$dir/bootstrap.sh"
                type install >/dev/null 2>&1 && install ""
            )
            # We can't use `(set -e;cmd1;cmd2;...;) || warning ...` or if-else here.
            # see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
            # shellcheck disable=SC2181
            [[ $? == 0 ]] || warning "Failed installing $dir"
        }
    done
}

uninstall() {
    alldirs=("$@")
    [[ $1 == 'all' ]] && {
        mapfile -t alldirs < <(ls)
        echo -n 'Uninstall everything? [y/N]: '
        read -r ans
        [[ $ans == y ]] || exit 0
    }

    for dir in "${alldirs[@]}"; do
        # shellcheck source=vim/bootstrap.sh
        [ -f "$dir/bootstrap.sh" ] && {
            (
                set -e
                source "$dir/bootstrap.sh"
                type uninstall >/dev/null 2>&1 && uninstall ""
            )

            # shellcheck disable=SC2181
            [[ $? == 0 ]] || warning "Failed uninstalling $dir"
        }
    done
}

"$@"
