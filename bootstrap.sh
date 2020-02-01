#!/bin/bash
# shellcheck disable=SC1090

DOTFILES_ROOT=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd
)
export DOTFILES_ROOT

source "${DOTFILES_ROOT}/.lib/utils.sh"
source "${DOTFILES_ROOT}/.lib/distro.sh"

# This script requires bash >= 4.3, since it uses `declare -n`
if [[ ${BASH_VERSINFO[0]} -lt 4 ]] ||
    [[ ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 3 ]]; then
    echo "This script requires Bash version >= 4.3"
    exit 1
fi

[[ $EUID -eq 0 ]] && {
    error "This script cannot be run as root," \
        "as it might cause unexpected damage." >&2
    exit 1
}

# Fake a `sudo' command, since termux does not have a sudo command
[[ $DISTRO == "termux" ]] && {
    sudo() {
        while [[ $1 =~ ^- ]]; do shift; done
        "$@"
    }
    export -f sudo
}

_OPTION_PATTERN='--?[[:alnum:]][[:alnum:]-]*$'

main() {
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
    l*) cmd="list" ;;
    n*) cmd="new" ;;
    *)
        error "Command '$cmd' not recognized. Run '${BASH_SOURCE[0]}' for help"
        exit 1
        ;;
    esac

    # List packages ############################################################
    ############################################################################
    [[ $cmd == "list" ]] && {
        while read -r dotfile; do
            if [[ -f $DOTFILES_ROOT/$dotfile/bootstrap.sh ]]; then
                echo "$dotfile"
            fi
        done < <(ls "$DOTFILES_ROOT")
        return 0
    }

    # Create a new package #####################################################
    ############################################################################
    [[ $cmd == "new" ]] && {
        info "Creating package '$1'"
        mkdir -p "$DOTFILES_ROOT/$1"
        echo "$_BOOTSTRAP_TEMPLATE" >"$DOTFILES_ROOT/$1/bootstrap.sh"
        return 0
    }

    # List/filter packages for install/uninstall/check #########################
    ############################################################################
    # Scan for all `bootstrap.sh` and run them
    local -a dotfiles=("$@")
    [[ $1 == 'all' ]] && mapfile -t dotfiles < <(ls "$DOTFILES_ROOT")

    # filter out invalid dotfiles
    local -a validDotfiles
    for dotfile in "${dotfiles[@]}"; do
        if [ -f "$DOTFILES_ROOT/$dotfile/bootstrap.sh" ]; then
            validDotfiles+=("$dotfile")
        fi
    done

    # update dotfiles list
    dotfiles=("${validDotfiles[@]}")
    unset validDotfiles

    # Parse tags ###############################################################
    ############################################################################
    local require_root=false
    #    for dir in "${dirs[@]}"; do
    #        [ -f "$DOTFILES_ROOT/$dir/bootstrap.sh" ] || continue
    #        (
    #            set -eo pipefail
    #            # shellcheck source=./vim/bootstrap.sh
    #            source "$DOTFILES_ROOT/$dir/bootstrap.sh"
    #
    #            for tag in "${tags[@]}"; do
    #                if [[ $tag == "root" ]]; then
    #                    require_root=true
    #                fi
    #            done
    #        )
    #    done

    # Parse dependency graph ###################################################
    ############################################################################
    # Check for dependency loop
    $opt_i_checkdeps && {
        dependencyLoopDetection "${dotfiles[@]}" || {
            error "Depencency checking failed"
            return 1
        }

        # add all dependency to 'dotfiles' and correct their order,
        # if automatic dependency install is enabled
        $opt_i_installdeps && {
            mapfile -t dotfiles < <(listAndSortDependencies "${dotfiles[@]}")
        }
    }

    # Require and hold root access #############################################
    ############################################################################
    if [[ $cmd == "install" ]]; then
        if $opt_i_installdeps || $require_root; then
            # At least `sudo` is needed
            type sudo >/dev/null 2>&1 || {
                error "the 'sudo' program is needed for running this script"
                exit 1
            }

            # Require root privilege
            sudo -v || {
                if $require_root; then
                    warning "Require root failed." \
                        "The following packages will NOT be installed:"
                    # TODO:
                elif $opt_i_installdeps; then
                    error "Automatically installing dependencies requires root."
                    return 1
                fi
            }

            # keep sudo credential cache up-to-date
            while true; do
                sleep 300
                sudo -n true
                kill -0 "$$" 2>/dev/null || exit
            done &
        fi
    fi

    # Install/Uninstall/Check packages #########################################
    ############################################################################
    for dotfile in "${dotfiles[@]}"; do
        # A failure of one dotfile installation will stop successive install,
        # as there might be a dependency chain in the dotfiles list
        info "Processing $dotfile"
        installDotfile "$dotfile" || return 1
    done
}

# $@: all dotfiles to install
dependencyLoopDetection() {
    local -a examQueue
    for dotfile in "$@"; do
        examQueue+=("$dotfile")
        examQueueLevel+=("1")
    done

    # non-recursive DFS to find all dependency loops
    local -A dependsSet
    local -a dependsStack # dependsStack[-1] is stack top
    while [[ ${#examQueue[@]} -ne 0 ]]; do
        local curDotfile="${examQueue[0]}"
        local curDotfileLevel="${examQueueLevel[0]}"
        examQueue=("${examQueue[@]:1}")
        examQueueLevel=("${examQueueLevel[@]:1}")

        # set depends stack to correct level
        while [[ ${#dependsStack[@]} -ne $((curDotfileLevel - 1)) ]]; do
            unset dependsSet["${dependsStack[-1]}"]
            dependsStack=("${dependsStack[@]::${#dependsStack[@]}-1}")
        done

        # check for dependency loop
        if [[ -n ${dependsSet[$curDotfile]} ]]; then
            local loop
            for depend in "${dependsStack[@]}"; do
                if [[ "$depend" == "$curDotfile" ]]; then
                    loop+="[1m[31m${depend}[0m -> "
                else
                    loop+="$depend -> "
                fi
            done
            loop+="[1m[31m$curDotfile[0m"
            error "Dependency loop detected: $loop"
            unset loop
            return 1
        fi

        # read all dependency of current dotfile
        if [[ ! -f "$DOTFILES_ROOT/$curDotfile/bootstrap.sh" ]]; then
            chain=$(printf "%s -> " "${dependsStack[@]}")
            chain+="$curDotfile"
            error "Dependency chain: $chain," \
                "but '$DOTFILES_ROOT/$curDotfile/bootstrap.sh' does not exist."
            return 1
        fi
        mapfile -t depends < <(
            set -eo pipefail
            source "$DOTFILES_ROOT/$curDotfile/bootstrap.sh" >/dev/null 2>&1
            for depend in "${depends[@]}"; do
                if [[ $depend =~ d[[:alnum:]]*:[[:print:]]+ ]]; then
                    echo "${depend#d*:}"
                fi
            done
        )
        if [[ ${#depends[@]} -ne 0 ]]; then
            examQueue=("${depends[@]}" "${examQueue[@]}")
            for ((i = 0; i < ${#depends[@]}; ++i)); do
                examQueueLevel=("$((curDotfileLevel + 1))" "${examQueueLevel[@]}")
            done
            dependsStack+=("$curDotfile")
            dependsSet["$curDotfile"]=1
        fi
    done
    return 0
}

# $@ all dotfiles to install
listAndSortDependencies() {
    local -a examQueue
    for dotfile in "$@"; do
        examQueue+=("$dotfile")
    done

    # Use BFS to get the topological order
    # Yeah I know this function can be merged with dependencyLoopDetection
    # but for the sake of simplicity and readability I'll just use BFS here
    for ((i = 0; i < ${#examQueue[@]}; ++i)); do
        local curDotfile="${examQueue[$i]}"
        mapfile -t depends < <(
            set -eo pipefail
            source "$DOTFILES_ROOT/$curDotfile/bootstrap.sh" >/dev/null 2>&1
            for depend in "${depends[@]}"; do
                if [[ $depend =~ d[[:alnum:]]*:[[:print:]]+ ]]; then
                    echo "${depend#d*:}"
                fi
            done
        )
        if [[ ${#depends[@]} -ne 0 ]]; then
            examQueue=("${examQueue[@]}" "${depends[@]}")
        fi
    done

    local -A uniqueSet
    for ((i = 1; i <= ${#examQueue[@]}; ++i)); do
        if [[ -z ${uniqueSet[${examQueue[-$i]}]} ]]; then
            uniqueSet[${examQueue[-$i]}]=1
            echo "${examQueue[-$i]}"
        fi
    done
}

# $1: name of the dotfile directory
installDotfile() {
    local dotfile=$1
    (# run in subshell. exit when any error happens
        set -eo pipefail

        # shellcheck source=./vim/bootstrap.sh
        source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null 2>&1

        declare -a missing_files_install=()
        declare -a missing_files_check=()
        # Check dependency files before installing
        [[ $cmd == "install" ]] && $opt_i_checkdeps && {
            for item in "${depends[@]}"; do
                if [[ $item =~ fi[[:alnum:]]*:[[:print:]]+ ]]; then
                    # item is a file
                    [[ -e "${item#fi*:}" ]] || {
                        missing_files_check+=("${item}")
                        missing_files_install+=("${item}")
                    }
                elif [[ $item =~ v[[:alnum:]]*:[[:print:]]+ ]]; then
                    # item is virtual
                    missing_files_install+=("${item}")
                elif [[ $item =~ fu[[:alnum:]]*:[[:print:]]+ ]]; then
                    # Use a function to judge if item exists
                    ${item#fu*:} || {
                        missing_files_check+=("${item}")
                        missing_files_install+=("${item}")
                    }
                elif [[ $item =~ d[[:alnum:]]*:[[:print:]]+ ]]; then
                    # Check for invalid key in 'packages' array
                    [[ -z ${packages[$item]} ]] ||
                        warning "$dotfile: [$item]=${packages[$item]} in the" \
                            "'packages' array is ignored. Please consider" \
                            "removing it."
                    # Skip. internal dependency is already parsed.
                else
                    # item is a executable
                    command -v "${item#e*:}" >/dev/null 2>&1 || {
                        missing_files_check+=("${item}")
                        missing_files_install+=("${item}")
                    }
                fi
            done
            [[ ${#missing_files_check[@]} -gt 0 ]] && ! $opt_i_installdeps && {
                warning "Dependency missing: ${missing_files_check[*]}"
                exit 1
            }
            unset missing_files_check
        }

        # Install dependencies
        [[ $cmd == "install" ]] && $opt_i_installdeps && {
            # Install packages
            for file in "${missing_files_install[@]}"; do
                declare pkg=${packages[$file]}
                if [[ -n $pkg ]]; then
                    if [[ $pkg =~ f[[:alnum:]]*:[[:print:]]+ ]]; then
                        # package should be installed through function
                        ${pkg#f*:}
                    else
                        # installed package through system package manager
                        install_pkg_command="install_system_package_${DISTRO} ${pkg#s*:}"
                        $install_pkg_command || return 1
                    fi
                else
                    warning "Cannot meet dependency '${file}':" \
                        "it's not defined in the 'packages' dict"
                fi
            done
        }

        if [[ $(type -t "$cmd") == "function" ]]; then
            $cmd
        else
            warning "No '$cmd()' found in '$dotfile/bootstrap.sh', skipping."
        fi
    )
    # We can't use `(set -e;cmd1;cmd2;...;) || warning ...` or if-else here.
    # see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
    # shellcheck disable=SC2181
    [[ $? == 0 ]] || {
        warning "Failed ${cmd}ing $dotfile"
        return 1
    }
    # TODO: break this function into 3 functions
}

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

    l*, list
        list all available packages

    n*, new
        create a new package with template

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

# shellcheck disable=SC2016
_BOOTSTRAP_TEMPLATE="\
"'#!/bin/bash
# shellcheck disable=SC1090

source "$DOTFILES_ROOT/.lib/utils.sh"
source "$DOTFILES_ROOT/.lib/distro.sh"
source "$DOTFILES_ROOT/.lib/symlink.sh"
source "$DOTFILES_ROOT/.lib/transaction.sh"

THISDIR=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd -P
)

declare -a depends=()
export depends

declare -A packages=()
export packages

install() {
    :
}

uninstall() {
    :
}
'

main "$@"
