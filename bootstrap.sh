#!/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2181

# SOME CONFIG THAT CAN BE CHANGED ##############################################
################################################################################
# additional directory to search for dotfiles configs (relative to DOTFILES_ROOT)
ADDITIONAL_DIRS=(Software)

# compilation job count when building things in user mode
JOB_COUNT=$(command -v nproc >/dev/null 2>&1 && nproc --all)
JOB_COUNT=${JOB_COUNT:-8}
JOB_COUNT=$((JOB_COUNT / 2))
[[ $JOB_COUNT -le 0 ]] && JOB_COUNT=1
export JOB_COUNT

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
DOTFILES_ROOT=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd
)
export DOTFILES_ROOT

USER_PREFIX="$HOME/.local"
export USER_PREFIX

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
    local -A list_options=(
        [rundeps]=false
        [makedeps]=false
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
            "-j" | "--jobs")
                shift
                export JOB_COUNT=$1
                local re='^[1-9][0-9]*$'
                [[ $JOB_COUNT =~ $re ]] || {
                    error "job count must be a positive integer"
                    return 1
                }
                ;;
            *)
                error "Option $1 unrecognized"
                return 1
                ;;
            esac
            shift
        done

        # require root if not in usermode
        ${install_options[usermode]} || require_and_hold_root_access || return 1
        ${install_options[usermode]} && {
            export PATH="$USER_PREFIX/bin:$PATH"
            export LD_LIBRARY_PATH="$USER_PREFIX/lib64:$USER_PREFIX/lib:$LD_LIBRARY_PATH"
        }

        # dotfiles to install
        local -a dotfiles

        # filter a list of valid dotfiles
        local valid_dotfiles
        valid_dotfiles="$(filter_valid_dotfiles "$@")"
        if [[ -n $valid_dotfiles ]]; then
            mapfile -t dotfiles <<<"$valid_dotfiles"
        else
            warning "No dotfile to install..."
            return 0
        fi

        # Parse dependency graph
        ${install_options[checkdeps]} && {
            if ${install_options[installdeps]}; then
                # Check for dependency loop, including makedepends
                dependency_loop_detection makedepends "${dotfiles[@]}" || {
                    error "Depencency checking failed"
                    return 1
                }

                # add all dependency, including makedepends to 'dotfiles' and correct their order,
                mapfile -t dotfiles < <(list_and_sort_dependencies makedepends "${dotfiles[@]}")
            else
                # Only check for running depends (the `depends` vector)
                dependency_loop_detection rundepends "${dotfiles[@]}" || {
                    error "Dependency checking failed"
                    return 1
                }
            fi
        }
        echo "dotfiles to check/install: ${dotfiles[*]}"
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
        while [[ $1 =~ $_OPTION_PATTERN ]]; do
            case $1 in
            '-d' | '--depends')
                list_options[rundeps]=true
                ;;
            '-m' | '--makedepends')
                list_options[makedeps]=true
                ;;
            *)
                error "Option $1 unrecognized"
                exit 1
                ;;
            esac
            shift
        done

        # dotfiles to list
        local -a dotfiles

        # filter a list of valid dotfiles
        local valid_dotfiles
        valid_dotfiles="$(filter_valid_dotfiles "$@")"
        if [[ -n $valid_dotfiles ]]; then
            mapfile -t dotfiles <<<"$valid_dotfiles"
        else
            warning "No dotfile to list..."
            return 0
        fi

        if ${list_options[makedeps]}; then
            # Check for dependency loop, including makedepends
            dependency_loop_detection makedepends "${dotfiles[@]}" || {
                error "Depencency checking failed"
                return 1
            }
            # add all dependency, including makedepends to 'dotfiles' and correct their order,
            mapfile -t dotfiles < <(list_and_sort_dependencies makedepends "${dotfiles[@]}")
            echo "${dotfiles[*]}"
        elif ${list_options[rundeps]}; then
            # Check for dependency loop, including makedepends
            dependency_loop_detection rundepends "${dotfiles[@]}" || {
                error "Depencency checking failed"
                return 1
            }
            # add all dependency, including makedepends to 'dotfiles' and correct their order,
            mapfile -t dotfiles < <(list_and_sort_dependencies rundepends "${dotfiles[@]}")
            echo "${dotfiles[*]}"
        else
            echo "${dotfiles[*]}"
        fi

        return 0
        ;;
    n*)
        cmd="new" # create a new package
        [[ $cmd == "new" ]] && {
            info "Creating package '$1'"
            mkdir -p "$DOTFILES_ROOT/$1"
            [[ -f "$DOTFILES_ROOT/$1/bootstrap.sh" ]] && {
                error "$DOTFILES_ROOT/$1/bootstrap.sh exists."
                return 1
            }
            echo "$_BOOTSTRAP_TEMPLATE" >"$DOTFILES_ROOT/$1/bootstrap.sh"
            return 0
        }
        ;;
    *)
        error "Command '$cmd' not recognized. Run '${BASH_SOURCE[0]}' for help"
        exit 1
        ;;
    esac

    # TODO: add tag support
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
# return: 1 if dependency has unknown prefix. 0 otherwise.
dependency_type_and_name() {
    local item="$1"
    if [[ $item =~ fi[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "file ${item#fi*:}"
    elif [[ $item =~ v[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "virtual ${item#v*:}"
    elif [[ $item =~ fu[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "function ${item#fu*:}"
    elif [[ $item =~ d[[:alnum:]]*:[[:print:]]+ ]]; then
        local found=false
        for dir in "" "${ADDITIONAL_DIRS[@]}"; do
            if [[ -d $DOTFILES_ROOT/$dir/${item#d*:} ]] && [[ -f $DOTFILES_ROOT/$dir/${item#d*:}/bootstrap.sh ]]; then
                found=true
                echo "dotfile ${dir:+${dir}/}${item#d*:}"
                break
            fi
        done
        # if not found, let upper level handle this
        $found || echo "dotfile ${item#d*:}"
    elif [[ $item =~ e[[:alnum:]]*:[[:print:]]+ ]]; then
        echo "executable ${item#e*:}"
    elif [[ $item =~ [[:alnum:]]+:[[:print:]]+ ]]; then
        echo "unknown ${item#*:}"
        return 1
    else
        # noprefix, first treat as executable
        local is_executable=true
        if ! command -v "$item" >/dev/null 2>&1; then
            # if command not found, and bootstrap script for the dotfile
            # of same name is found, treat as dotfile
            for dir in "" "${ADDITIONAL_DIRS[@]}"; do
                if [[ -d $DOTFILES_ROOT/$dir/$item ]] && [[ -f $DOTFILES_ROOT/$dir/$item/bootstrap.sh ]]; then
                    is_executable=false
                    echo "dotfile ${dir:+${dir}/}$item"
                    break
                fi
            done
        fi
        # in all other cases still treat as executable
        $is_executable && echo "executable $item"
    fi
}

# $1: <rundepends|makedepends>, decide which type of dependency to include.
#     Note that makedepends implies rundepends
# ${@:1}: all dotfiles to install
dependency_loop_detection() {
    local add_makedepends=false
    [[ $1 == makedepends ]] && add_makedepends=true
    shift

    local -a exam_queue
    local -a exam_queue_level
    for dotfile in "$@"; do
        exam_queue+=("$dotfile")
        exam_queue_level+=("1")
    done

    # non-recursive DFS to find all dependency loops
    local -A deps_set
    local -a deps_stack # deps_stack[-1] is stack top
    while [[ ${#exam_queue[@]} -ne 0 ]]; do
        local cur_dotfile="${exam_queue[0]}"
        local cur_dotfile_level="${exam_queue_level[0]}"
        exam_queue=("${exam_queue[@]:1}")
        exam_queue_level=("${exam_queue_level[@]:1}")

        # set depends stack to correct level
        while [[ ${#deps_stack[@]} -ne $((cur_dotfile_level - 1)) ]]; do
            unset deps_set["${deps_stack[-1]}"]
            deps_stack=("${deps_stack[@]::${#deps_stack[@]}-1}")
        done

        # check for dependency loop
        if [[ -n ${deps_set[$cur_dotfile]} ]]; then
            local loop
            for depend in "${deps_stack[@]}"; do
                if [[ "$depend" == "$cur_dotfile" ]]; then
                    loop+="[1m[31m${depend}[0m -> "
                else
                    loop+="$depend -> "
                fi
            done
            loop+="[1m[31m$cur_dotfile[0m"
            error "Dependency loop detected: $loop"
            unset loop
            return 1
        fi

        # read all dependency of current dotfile
        if [[ ! -f "$DOTFILES_ROOT/$cur_dotfile/bootstrap.sh" ]]; then
            local chain
            chain=$(printf "%s -> " "${deps_stack[@]}")
            chain+="$cur_dotfile"
            error "Dependency chain: $chain," \
                "but 'bootstrap.sh' script for '$cur_dotfile' does not exist."
            return 1
        fi

        local -a depends
        mapfile -t depends < <(extract_dotfile_depends rundepends "$cur_dotfile")

        # add makedepends if required
        if $add_makedepends; then
            local -a makedepends
            mapfile -t makedepends < <(extract_dotfile_depends makedepends "$cur_dotfile")
            depends=("${makedepends[@]}" "${depends[@]}")
        fi

        if [[ ${#depends[@]} -ne 0 ]]; then
            exam_queue=("${depends[@]}" "${exam_queue[@]}")
            for ((i = 0; i < ${#depends[@]}; ++i)); do
                exam_queue_level=("$((cur_dotfile_level + 1))" "${exam_queue_level[@]}")
            done
            deps_stack+=("$cur_dotfile")
            deps_set["$cur_dotfile"]=1
        fi
    done
    return 0
}

# $1: <rundepends|makedepends>, decide which type of dependency to include.
#     Note that makedepends implies rundepends
# ${@:1} all dotfiles to install
list_and_sort_dependencies() {
    local add_makedepends=false
    [[ $1 == makedepends ]] && add_makedepends=true
    shift

    local -a exam_queue
    for dotfile in "$@"; do
        exam_queue+=("$dotfile")
    done

    # Use BFS to get the topological order.
    # Yeah I know this function can be merged with dependency_loop_detection,
    # but for the sake of simplicity and readability I'll just use BFS here.
    for ((i = 0; i < ${#exam_queue[@]}; ++i)); do
        local cur_dotfile="${exam_queue[$i]}"
        local -a depends
        mapfile -t depends < <(extract_dotfile_depends rundepends "$cur_dotfile")

        # add makedepends in front of rundepends, if required
        if $add_makedepends; then
            local -a makedepends
            mapfile -t makedepends < <(extract_dotfile_depends makedepends "$cur_dotfile")
            depends=("${makedepends[@]}" "${depends[@]}")
        fi

        if [[ ${#depends[@]} -ne 0 ]]; then
            exam_queue+=("${depends[@]}")
        fi
    done

    local -A unique_set
    for ((i = 1; i <= ${#exam_queue[@]}; ++i)); do
        if [[ -z ${unique_set[${exam_queue[-$i]}]} ]]; then
            unique_set[${exam_queue[-$i]}]=1
            echo "${exam_queue[-$i]}"
        fi
    done
}

# Extract `d*:` types dependencies from dotfiles' bootstrap file
# $1: <rundepends|makedepends>, decide which type of dependency to include.
# $2: name of the dotfile
extract_dotfile_depends() {
    if [[ $1 == makedepends ]]; then
        (
            set -eo pipefail
            # avoid variable contamination of parent shell
            unset makedepends
            source "$DOTFILES_ROOT/$2/bootstrap.sh" >/dev/null 2>&1
            for depend in "${makedepends[@]}"; do
                read -r dep_type dep_name <<<"$(dependency_type_and_name "$depend")"
                if [[ $dep_type == dotfile ]]; then
                    echo "$dep_name"
                fi
            done
        )
    elif [[ $1 == rundepends ]]; then
        (
            set -eo pipefail
            # avoid variable contamination of parent shell
            unset depends
            source "$DOTFILES_ROOT/$2/bootstrap.sh" >/dev/null 2>&1
            for depend in "${depends[@]}"; do
                read -r dep_type dep_name <<<"$(dependency_type_and_name "$depend")"
                if [[ $dep_type == dotfile ]]; then
                    echo "$dep_name"
                fi
            done
        )
    else
        error "extract_dotfile_depends: Unrecognized option $1"
        exit 1
    fi
}

# require: 'install_options' map set
# require: 'dotfiles' array set
install_dotfiles() {
    # Three steps to install all the dotfiles. the first two steps are skipped
    # if 'install_options[checkdeps]' is false

    for dotfile in "${dotfiles[@]}"; do
        info "Processing $dotfile ..."
        ${install_options[checkdeps]} && {
            # 1. check if all dependencies in the 'depends' array, if dependency is not
            # met, check if there's a entry in the 'packages' array to install it
            local -a missing_deps=()

            local missing_deps_list=""
            missing_deps_list=$(
                # run in subshell. exit when any error happens
                set -eo pipefail

                # Do not redirect stderror to allow error reporting in dotfile scripts
                # shellcheck source=./vim/bootstrap.sh
                source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null

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
                        set +e
                        (
                            set -e
                            ${item#fu*:}
                        )
                        [[ $? == 0 ]] || {
                            missing_deps_check+=("${item}")
                            missing_deps_install+=("${item}")
                        }
                        set -e
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
                    elif [[ $dep_type == 'unknown' ]]; then
                        error "$dotfile: unrecognized dependency prefix in '${item}'"
                        return 1
                    fi
                done

                if [[ ${#missing_deps_check[@]} -gt 0 ]]; then
                    warning "$dotfile: Dependency missing: ${missing_deps_check[*]}" >&2
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
            [[ $? == 0 ]] || {
                error "Unable to meet dependency(s), aborting... "
                return 1
            }

            # note that '<<<' always create a '\n' terminated string
            [[ -n $missing_deps_list ]] &&
                mapfile -t missing_deps <<<"$missing_deps_list"

            ${install_options[installdeps]} && {
                # 2. install all the missing dependencies
                (
                    set -eo pipefail
                    # shellcheck source=./vim/bootstrap.sh
                    source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null 2>&1

                    for dep in "${missing_deps[@]}"; do
                        declare pkg="${packages["$dep"]}"
                        if [[ $pkg =~ f[[:alnum:]]*:[[:print:]]+ ]]; then

                            # package should be installed through function, in a subshell,
                            # so that set -e works correctly (both "exceptions" and returned error code are captured)
                            # We have to use this crooked way to simulate try-catch ...
                            # As above, see https://stackoverflow.com/questions/29532904/bash-subshell-errexit-semantics
                            set +e
                            (
                                set -e
                                ${pkg#f*:}
                            )
                            [[ $? == 0 ]] || {
                                error "$dotfile: Failed executing function ${pkg#f*:}."
                                return 1
                            }
                            set -e
                        else
                            # package should be installed through package manager.
                            install_pkg_command="install_system_package_${DISTRO} ${pkg#s*:}"
                            set +e
                            (
                                set -e
                                $install_pkg_command
                            )
                            [[ $? == 0 ]] || {
                                error "$dotfile: Failed installing system package ${pkg#s*:} (for dependency $dep)."
                                return 1
                            }
                            set -e
                        fi
                    done
                )
                [[ $? == 0 ]] || {
                    error "Dependency installation failed, aborting... "
                    return 1
                }
            }
        }

        # 3. install dotfiles
        (
            set -eo pipefail
            # shellcheck source=./vim/bootstrap.sh
            source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null

            if [[ $(type -t "install") == "function" ]]; then
                install >/dev/null
            else
                warning "'install()' not defined in '$dotfile/bootstrap.sh', skipping."
            fi
        )
        [[ $? == 0 ]] || {
            warning "Failed installing $dotfile"
            return 1
        }

        local post_install_func
        post_install_func="$(
            set -eo pipefail
            # shellcheck source=./vim/bootstrap.sh
            source "$DOTFILES_ROOT/$dotfile/bootstrap.sh" >/dev/null

            if [[ $(type -t "post_install") == "function" ]]; then
                type post_install
            fi
        )"

        # the #*$'\n' suffix removes the first line of the output of `type`,
        # which should be "xxx is a function". I don't to use sed/grep here
        # as it's not pure bash.
        post_install_func="${post_install_func#*$'\n'}"
        [[ -n ${post_install_func} ]] && {
            info "Executing post_install function of $dotfile"
            eval "${post_install_func}"

            post_install || {
                error "$dotfile: Failed evaluating the post_install function. Aborting to avoid subsequent failures..."
                return 1
            }

            unset post_install
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
    ${BASH_SOURCE[0]} list -d vim tmux

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

    -j <JOB_COUNT>, --jobs <JOB_COUNT>
        Number of parallel jobs for the automake system. Only applies when -u is specified. Defaults to number of cores or 4 (if number of cores cannot be detected).

[1mOPTIONS (uninstall)[0m
    Note that this bootstrap script does not provide functionality to uninstall previously installed dependencies. Please use your distro's package manager or manually uninstall the dependencies. You can check each dotfiles' bootstrap.sh to see what is installed exactly.

[1mOPTIONS (list)[0m
    -d, --depends
        Also list dependency chain for each package

    -m, --makedepends (overrides -d)
        Also list makedepends chain for each package.

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
declare -a makedepends=()
declare -A packages=()

declare -a tags=(t:r:arch t:u:arch)

if $ISROOT; then
    if [[ $DISTRO == arch ]]; then
        # packages+=()
        : # add more distros with #elif
    fi
else
    # non-root installation
    # makedepends=(gnu-tools tar curl)
    packages+=()
    # installPackage() {
    #     local tempdir
    #     tempdir=$(mktemp -d)
    #     pushd "$tempdir" || exit 1
    #     # ...
    #     popd || exit 1
    #     rm -rf "$tempdir"
    # }
fi

export depends
export makedepends
export packages
export tags

################################################################################

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
