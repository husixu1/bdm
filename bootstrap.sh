#!/bin/bash

set -euo pipefail # Strict mode

source .lib/utils.sh

DOTFILES_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit; pwd)
export DOTFILES_ROOT

install() {
    # At least `sudo` is needed
    command -v sudo >/dev/null 2>&1 || {
        error "the 'sudo' program is needed for running this script"
        exit 1
    }

    # Require root previliges
    sudo -v

    # keep sudo credential cache up-to-date
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &

    # Scan for all `bootstrap.sh` and run them
    alldirs=("$@")
    [[ $1 == 'all' ]] && mapfile -t alldirs < <(ls)


    printError(){
        error "'$dir' installation failed"
    }
    trap printError EXIT
    for dir in "${alldirs[@]}"; do
        # shellcheck source=vim/bootstrap.sh
        [ -f "$dir/bootstrap.sh" ] && {
            source "$dir/bootstrap.sh"
            installSystemPackages "${require[@]}"

            type prepare >/dev/null 2>&1 && prepare
            type install >/dev/null 2>&1 && install
        }
    done
    trap - EXIT
}

uninstall() {
    for dir in "${alldirs[@]}"; do
        echo "$dir"
    done
}

"$@"
