#!/bin/bash

# This script requires bash >= 4.3, since it uses `declare -n`
if [[ ${BASH_VERSINFO[0]} -lt 4 ]] ||
    [[ ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 3 ]]; then
    echo "This script requires Bash version >= 4.3"
    exit 1
fi

DOTFILES_ROOT=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd
)
export DOTFILES_ROOT

# shellcheck source=./.lib/utils.sh
source "${DOTFILES_ROOT}/.lib/utils.sh"

_HELP_MESSAGE="\
[1mSYNOPSIS[0m
    ${BASH_SOURCE[0]} [4mCOMMAND[0m [OPTIONS] [4mPKGS[0m...

    e.g.

    ${BASH_SOURCE[0]} install vim git
    ${BASH_SOURCE[0]} install -i all
    ${BASH_SOURCE[0]} uninstall git
    ${BASH_SOURCE[0]} check tmux

[1mCOMMAND[0m
    i*, install
        install packages specified by PKGS

    u*, uninstall
        install packages specified by PKGS

    c*, check
        check whether a package is installed

[1mOPTIONS (install)[0m
    -n, --no-checkdeps
        Skip dependency checking and install dotfiles anyway. Might cause
        installation failure

    -c, --checkdeps (default)
        Checks dependencies before installing. If dependency checking fails,
        the dotfiles will not be installed.

    -i, --installdeps (implies -c, overrides -n, requires root)
        Install dependencies automatically. Requires root priviledge. Requires
        the \`sudo\` executable in \$PATH

[1mOPTIONS (uninstall)[0m

[1mOPTIONS (check)[0m

[1mPKGS[0m
    <name>
        name of a package directory (e.g. vim)

    all
        all avaliable packages
"

_OPTION_PATTERN='--?[[:alnum:]][[:alnum:]-]*$'

dispatchCommand() {
    [[ $# -eq 0 ]] && {
        echo "$_HELP_MESSAGE"
        return 0
    }

    # Parse command line #######################################################
    ############################################################################

    # get command
    local cmd=$1
    shift
    local opt_i_checkdeps=true
    local opt_i_installdeps=false

    case $cmd in
    i*)
        cmd="install"
        # get options, formalize command
        while [[ $1 =~ $_OPTION_PATTERN ]]; do
            case $1 in
            "-n" | "--no-checkdeps") opt_i_checkdeps=false ;;
            "-c" | "--checkdeps") opt_i_checkdeps=true ;;
            "-i" | "--installdeps")
                opt_i_checkdeps=true
                opt_i_installdeps=true
                ;;
            *)
                error "Option $1 unrecognized"
                exit 1
                ;;
            esac
            shift
        done
        ;;
    u*)
        cmd="uninstall"
        # get options, formalize command
        while [[ $1 =~ $_OPTION_PATTERN ]]; do
            case $1 in
            *)
                error "Option $1 unrecognized"
                exit 1
                ;;
            esac
            shift
        done
        ;;
    c*)
        cmd="check"
        # get options, formalize command
        while [[ $1 =~ $_OPTION_PATTERN ]]; do
            case $1 in
            *)
                error "Option $1 unrecognized"
                exit 1
                ;;
            esac
            shift
        done
        ;;

    *)
        error "Command '$cmd' not recognized. Run '${BASH_SOURCE[0]}' for help"
        exit 1
        ;;
    esac

    # Grant and hold root access ###############################################
    ############################################################################

    [[ $cmd == "install" ]] && $opt_i_installdeps && {
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
    }

    # Install/Uninstall/Check packages #########################################
    ############################################################################

    # Scan for all `bootstrap.sh` and run them
    local -a dirs=("$@")

    [[ $1 == 'all' ]] && mapfile -t dirs < <(ls "${DOTFILES_ROOT}")

    for dir in "${dirs[@]}"; do
        info "Processing $dir"

        [ -f "$DOTFILES_ROOT/$dir/bootstrap.sh" ] || {
            warning "Cannot find $dir/bootstrap.sh. Processing aborted."
            continue
        }

        (# run in subshell. exit when any error happens
            set -eo pipefail

            # shellcheck source=./vim/bootstrap.sh
            source "$DOTFILES_ROOT/$dir/bootstrap.sh"

            # Check dependency files before installing
            declare -a missing_files=()
            [[ $cmd == "install" ]] && $opt_i_checkdeps && {
                declare -a virtual_files=()
                for item in "${depends[@]}"; do
                    if [[ $item =~ fi[[:alnum:]]*:[[:print:]]+ ]]; then
                        # item is a file
                        [[ -e "${item#fi*:}" ]] || missing_files+=("${item}")
                    elif [[ $item =~ v[[:alnum:]]*:[[:print:]]+ ]]; then
                        # item is virtual
                        virtual_files+=("${item}")
                    elif [[ $item =~ fu[[:alnum:]]*:[[:print:]]+ ]]; then
                        # Use a function to judge if item exists
                        ${item#fu*:} || missing_files+=("${item}")
                    else
                        # item is a executable
                        command -v "${item#e*:}" >/dev/null 2>&1 ||
                            missing_files+=("${item}")
                    fi
                done
                [[ ${#missing_files[@]} -gt 0 ]] && ! $opt_i_installdeps && {
                    warning "Dependency missing: ${missing_files[*]}"
                    exit 1
                }
                missing_files+=("${virtual_files[@]}")
            }

            # Install dependencies
            [[ $cmd == "install" ]] && $opt_i_installdeps && {
                # Install packages
                for file in "${missing_files[@]}"; do
                    declare pkg=${packages[$file]}
                    if [[ -n $pkg ]]; then
                        if [[ $pkg =~ f[[:alnum:]]*:[[:print:]]+ ]]; then
                            # package should be installed through function
                            ${pkg#f*:}
                        else
                            # package should be installed through system package manager
                            install_pkg_command="install_system_package_${DISTRO} ${pkg#s*:}"
                            ${install_pkg_command}
                        fi
                    else
                        warning "Cannot install package to meet dependency '${file}'"
                    fi
                done
            }

            type "$cmd" >/dev/null 2>&1 && $cmd
        )

        # We can't use `(set -e;cmd1;cmd2;...;) || warning ...` or if-else here.
        # see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
        # shellcheck disable=SC2181
        [[ $? == 0 ]] || warning "Failed ${cmd}ing $dir"
    done
}

dispatchCommand "$@"

# TODO: make all variables and functions use underscore separated format
