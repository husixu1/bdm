#!/bin/env bash
# shellcheck disable=SC1090

# STARTUP CHECKING #############################################################
################################################################################
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

# EXPORTS ######################################################################
################################################################################
export DOTFILES_ROOT=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd
)
export USER_PREFIX="$HOME/.local"
export JOB_COUNT=4

# INIT & INCLUDES ##############################################################
################################################################################
source "$DOTFILES_ROOT/.lib/utils.sh"
source "$DOTFILES_ROOT/.lib/distro.sh"

# Termux Support ###############################################################
################################################################################
# Fake a `sudo' command, since termux does not have a sudo command
[[ $DISTRO == "termux" ]] && {
    sudo() {
        while [[ $1 =~ ^- ]]; do shift; done
        "$@"
    }
    export -f sudo
}

# FUNCTIONS ####################################################################
################################################################################
_OPTION_PATTERN='^--?[[:alnum:]][[:alnum:]-]*$'

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

    local -A install_options=(
        [checkdeps]=true
        [installdeps]=false
        [usermode]=false
    )

    # TODO: add a function to export dependency graph
    case $cmd in
    i*)
        cmd="install"
        # get options, formalize command
        while [[ $1 =~ $_OPTION_PATTERN ]]; do
            case $1 in
            "-n" | "--no-checkdeps") install_options[checkdeps]=false ;;
            "-c" | "--checkdeps") install_options[checkdeps]=true ;;
            "-i" | "--installdeps")
                install_options[checkdeps]=true
                install_options[installdeps]=true
                ;;
            "-u" | "--user")
                install_options[usermode]=true
                export ISROOT=false
                ;;
            "-p" | "--prefix")
                shift
                export USER_PREFIX=$1
                [[ -d $USER_PREFIX ]] || {
                    error "User prefix $USER_PREFIX does not exist. Please create it manually"
                    return 1
                }
                install_options[usermode]=true
                export ISROOT=false
                ;;
            *)
                error "Option $1 unrecognized"
                return
                ;;
            esac
            shift
        done

        # require root if not in usermode
        ${install_options[usermode]} || require_and_hold_root_access || return 1

        # dotfiles to install
        local -a dotfiles

        # TODO: before parsing dependency graph:
        # check non-prefixed depends. First mark them as executable (e*:). If they are satisfied and not in the `packages` dir, Search them in the `Software` dir and mark them as dotfiles (d*:). doing so alows adding extra software build scripts without doing changes on the original bootstrap script

        # Parse dependency graph
        ${install_options[checkdeps]} && {
            # Check for dependency loop
            dependency_loop_detection "${dotfiles[@]}" || {
                error "Depencency checking failed"
                return 1
            }

            # add all dependency to 'dotfiles' and correct their order,
            # if automatic dependency install is enabled
            ${install_options[installdeps]} && {
                mapfile -t dotfiles < <(list_and_sort_dependencies "${dotfiles[@]}")
            }
        }

        # filter a list of valid dotfiles
        local valid_dotfiles
        valid_dotfiles="$(filter_valid_dotfiles "$@")"
        if [[ -n $valid_dotfiles ]]; then
            mapfile -t dotfiles <<< "$valid_dotfiles"
        else
            warning "Not dotfiles to install..."
            return 0
        fi

        echo "dotfiles to install: ${dotfiles[*]}"
        echo -n "Proceed? [Y/n]: "
        read -r ans
        [[ $ans == n ]] && return 0

        install_dotfiles
        return $?
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
        uninstallDotfiles
        return $?
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
    l*)
        cmd="list" # List packages
        while read -r dotfile; do
            if [[ -f $DOTFILES_ROOT/$dotfile/bootstrap.sh ]]; then
                echo "$dotfile"
            fi
        done < <(ls "$DOTFILES_ROOT")
        return 0
        ;;
    n*)
        cmd="new" # create a new package
        [[ $cmd == "new" ]] && {
            info "Creating package '$1'"
            mkdir -p "$DOTFILES_ROOT/$1"
            echo "$_BOOTSTRAP_TEMPLATE" >"$DOTFILES_ROOT/$1/bootstrap.sh"
            return 0
        }
        ;;
    *)
        error "Command '$cmd' not recognized. Run '${BASH_SOURCE[0]}' for help"
        exit 1
        ;;
    esac

    # Parse tags ###############################################################
    ############################################################################

    # TODO: move these to install section
    # Install/Uninstall/Check packages #########################################
    ############################################################################
    for dotfile in "${dotfiles[@]}"; do
        # A failure of one dotfile installation will stop successive install,
        # as there might be a dependency chain in the dotfiles list
        info "Processing $dotfile"
        processDotfile "$dotfile" || return 1
    done
}

# $@: list of dotfiles. 'all' for every valid dotfiles
# print: list of valid dotfiles
filter_valid_dotfiles() {
    local -a dotfiles=("$@")
    [[ $1 == 'all' ]] && mapfile -t dotfiles < <(ls "$DOTFILES_ROOT")

    # filter out invalid dotfiles
    local -a valid_dotfiles
    for dotfile in "${dotfiles[@]}"; do
        if [ -f "$DOTFILES_ROOT/$dotfile/bootstrap.sh" ]; then
            valid_dotfiles+=("$dotfile")
        fi
    done

    # return
    for dotfile in "${valid_dotfiles[@]}"; do
        echo "$dotfile"
    done
}

require_and_hold_root_access() {
    # At least `sudo` is needed
    type sudo >/dev/null 2>&1 || {
        error "the 'sudo' program is needed for running this script"
        exit 1
    }

    # Require root privilege
    if sudo -v; then
        export ISROOT=true
    else
        warning "Require root failed."
        echo "All installation process will be done in user mode."
        echo -n "Those dotfiles that requires root are doomed to fail. Proceed? [y/N]: "
        read -r ans
        if [[ $ans != y ]]; then
            return 1
        fi
        export ISROOT=false
    fi

    # keep sudo credential cache up-to-date
    while true; do
        sleep 60
        sudo -n true
        kill -0 "$$" 2>/dev/null || exit
    done &
}

# $1 dependency string
# print: two string: <type> <name>, separated with space, can be read
# into variable with `read -r type name`
dependency_type_and_name() {
    if [[ $item =~ fi[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "file ${item#fi*:}"
    elif [[ $item =~ v[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "virtual ${item#v*:}"
    elif [[ $item =~ fu[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "function ${item#fu*:}"
    elif [[ $item =~ d[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "dotfile ${item#d*:}"
    else
        echo "executable ${item#e*:}"
    fi
}

# $@: all dotfiles to install
dependency_loop_detection() {
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
                read -r dep_type dep_name <<<"$(dependency_type_and_name "$depend")"
                if [[ $dep_type == dotfile ]]; then
                    echo "$dep_name"
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
list_and_sort_dependencies() {
    local -a examQueue
    for dotfile in "$@"; do
        examQueue+=("$dotfile")
    done

    # Use BFS to get the topological order
    # Yeah I know this function can be merged with dependency_loop_detection
    # but for the sake of simplicity and readability I'll just use BFS here
    for ((i = 0; i < ${#examQueue[@]}; ++i)); do
        local curDotfile="${examQueue[$i]}"
        mapfile -t depends < <(
            set -eo pipefail
            source "$DOTFILES_ROOT/$curDotfile/bootstrap.sh" >/dev/null 2>&1
            for depend in "${depends[@]}"; do
                read -r dep_type dep_name <<<"$(dependency_type_and_name "$depend")"
                if [[ $dep_type == dotfile ]]; then
                    echo "$dep_name"
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

# require: 'install_options' map set
# require: 'dotfiles' array set
install_dotfiles() {
    # Three steps to install all the dotfiles. the first two steps are skipped
    # if 'install_options[checkdeps]' is false

    ${install_options[checkdeps]} && {
        # 1. check if all dependencies in the 'depends' array, if dependency is not
        # met, check if there's a entry in the 'packages' array to install it
        local -A dotfile_deps_offset
        local -a missing_deps

        for dotfile in "${dotfiles[@]}"; do
            local -a missing_deps_install
            missing_deps_list=$(
                # run in subshell. exit when any error happens
                set -eo pipefail

                # shellcheck source=./vim/bootstrap.sh
                source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null 2>&1

                # these variables are defined in subshell and does not interfere with the variables outside
                declare -a missing_deps_install=()
                declare -a missing_deps_check=()

                # Check dependency files before installing
                for item in "${depends[@]}"; do
                    read -r dep_type dep_name <<<"$(dependency_type_and_name "${item}")"
                    if [[ $dep_type == 'file' ]]; then
                        # item is a file
                        [[ -e $dep_name ]] || {
                            missing_deps_check+=("${item}")
                            missing_deps_install+=("${item}")
                        }
                    elif [[ $dep_type == 'virtual' ]]; then
                        # item is virtual, skip checking, but list as install
                        missing_deps_install+=("${item}")
                    elif [[ $dep_type == 'function' ]]; then
                        # Use a function to judge if item exists
                        ${item#fu*:} || {
                            missing_deps_check+=("${item}")
                            missing_deps_install+=("${item}")
                        }
                    elif [[ $dep_type == 'executable' ]]; then
                        command -v "$dep_name" >/dev/null 2>&1 || {
                            missing_deps_check+=("${item}")
                            missing_deps_install+=("${item}")
                        }
                    elif [[ $dep_type == 'dotfile' ]]; then
                        # item is a dotfile
                        # Check for invalid key in 'packages' array
                        [[ -z ${packages[$item]} ]] ||
                            warning "$dotfile: [$item]=${packages[$item]} in the" \
                                "'packages' array is ignored. Please consider" \
                                "removing it."
                        # Skip. dotfile dependency is already handled before this checking step.
                    fi
                done

                if [[ ${#missing_deps_check[@]} -gt 0 ]]; then
                    warning "$dotfile: Dependency missing: ${missing_deps_check[*]}"
                fi
                unset missing_deps_check

                declare unable_to_meet_dependency=false
                for file in "${missing_deps_install[@]}"; do
                    # pass to outer shell
                    echo "$file"

                    # check if this dependency can be meet
                    declare pkg=${packages[$file]}
                    if [[ -z $pkg ]]; then
                        error "$dotfile: Cannot meet dependency '${file}': It's neither installed nor defined in the 'packages' map."
                        unable_to_meet_dependency=true
                    elif ! [[ $pkg =~ f[[:alnum:]]*:[[:print:]]+ ]] && ! $ISROOT; then
                        # installed package through system package manager
                        error "Cannot install package ${pkg#s*} with package manager without root access"
                        unable_to_meet_dependency=true
                        return 1
                    fi
                done

                if $unable_to_meet_dependency; then
                    return 1
                fi
                exit 0
            )
            # We can't use `(set -e;cmd1;cmd2;...;) || warning ...` or if-else here.
            # see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
            # shellcheck disable=SC2181
            [[ $? == 0 ]] || {
                error "Unable to meet dependency(s), aborting... "
                return 1
            }

            # note that '<<<' always create a '\n' terminated string
            [[ -n $missing_deps_list ]] &&
                mapfile -t missing_deps_install <<<"$missing_deps_list"
            dotfile_deps_offset["${dotfile}_start"]=${#missing_deps[@]}
            missing_deps+=("${missing_deps_install[@]}")
            dotfile_deps_offset["${dotfile}_end"]=${#missing_deps[@]}
        done

        # 2. install all the missing dependencies
        for dotfile in "${dotfiles[@]}"; do
            (
                set -eo pipefail
                # shellcheck source=./vim/bootstrap.sh
                source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null 2>&1

                for ((i = dotfile_deps_offset["${dotfile}_start"]; i < dotfile_deps_offset["${dotfile}_end"]; ++i)); do
                    declare dep="${missing_deps["$i"]}"
                    declare pkg="${packages["$dep"]}"
                    if [[ $pkg =~ f[[:alnum:]]*:[[:print:]]+ ]]; then
                        # package should be installed through function
                        ${pkg#f*:} || {
                            error "$dotfile: Failed executing function ${pkg#f*:}, function return code: $?."
                            return 1
                        }
                    else
                        # package should be installed through package manager.
                        install_pkg_command="install_system_package_${DISTRO} ${pkg#s*:}"
                        $install_pkg_command || {
                            error "$dotfile: Failed installing system package ${pkg#s*:}, command return code: $?."
                            return 1
                        }
                    fi
                done
            )
            # shellcheck disable=SC2181
            [[ $? == 0 ]] || {
                error "Dependency installation failed, aborting... "
                return 1
            }
        done
    }

    # 3. install dotfiles
    for dotfile in "${dotfiles[@]}"; do
        (
            set -eo pipefail
            # shellcheck source=./vim/bootstrap.sh
            source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null 2>&1

            if [[ $(type -t "install") == "function" ]]; then
                install
            else
                warning "'install()' not defined in '$dotfile/bootstrap.sh', skipping."
            fi
        )

        # shellcheck disable=SC2181
        [[ $? == 0 ]] || {
            warning "Failed installing $dotfile"
            return 1
        }
    done

    # TODO: test this function
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

    l*, list
        list all available packages

    n*, new
        create a new package with template

[1mOPTIONS (install)[0m
    -n, --no-checkdeps
        Skip software dependency checking and install dotfiles anyway.

    -c, --checkdeps (default)
        Checks dependencies before installing. If dependency checking fails, the dotfiles will not be installed.

    -i, --installdeps (implies -c, overrides -n)
        Install dependencies automatically.

    -u, --user
        Install everything in user mode (assume no root access is granted)

    -p <PFX>, --prefix <PFX> (implies -u)
        Prefix for installing packages in user mode. Defaults to $HOME/.local

[1mOPTIONS (uninstall)[0m
    Note that this bootstrap script does not provide functionality to uninstall previously installed dependencies. Please use your distro's package manager or manually uninstall the dependencies. You can check each dotfiles' bootstrap.sh to see what is installed exactly.

[1mPKGS[0m
    <name>
        name of a package directory (e.g. vim)

    <tag>
        packages tagged with <tag>

    all
        all avaliable packages
"

# shellcheck disable=SC2016
_BOOTSTRAP_TEMPLATE="\
"'#!/bin/env bash
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

declare -a tags=(t:r:arch t:u:arch)
export tags

if $ISROOT; then
    if [[ $DISTRO == arch ]]; then
        # packages+=()
        : # add more distros use #elif
    fi
else
    # depends+=(gcc make "${depends[@]}")
    : # non-root installation
fi

install() {
    transaction
    # transactionInstallSymlink "$THISDIR/a" "$LOCAL_CONFIG_DIR/b"
    commit
}

uninstall() {
    transaction
    # transactionRemoveSymlink "$THISDIR/a" "$LOCAL_CONFIG_DIR/b"
    commit
}
'

main "$@"
