#!/bin/bash

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

error() {
    echo "BOOTSTRAP-ERR: " "$@" >&2
}

warning() {
    echo "BOOTSTRAP-WRN: " "$@" >&2
}

info() {
    echo "BOOTSTRAP-INF: " "$@" >&1
}

# From https://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script
distro() {
    (
        if [ -f /etc/os-release ]; then
            # freedesktop.org and systemd
            . /etc/os-release
            OS=$NAME
            VER=$VERSION_ID
        elif type lsb_release >/dev/null 2>&1; then
            # linuxbase.org
            OS=$(lsb_release -si)
            VER=$(lsb_release -sr)
            VER=${VER%.*}
        elif [ -f /etc/lsb-release ]; then
            # For some versions of Debian/Ubuntu without lsb_release command
            . /etc/lsb-release
            OS=$DISTRIB_ID
            VER=$DISTRIB_RELEASE
            VER=${VER%.*}
        elif [ -f /etc/debian_version ]; then
            # Older Debian/Ubuntu/etc.
            OS=Debian
            VER=$(cat /etc/debian_version)
            VER=${VER%.*}
        elif command -v termux-setup-storage >/dev/null 2>&1; then
            OS="Termux"
            VER=$(uname -r)
        else
            # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
            OS=$(uname -s)
            VER=$(uname -r)
        fi

        if [[ ${OS} =~ ^Arch || ${OS} =~ ^Manjaro ]]; then echo "arch"
        elif [[ ${OS} =~ ^Debian ]]; then echo "debian_${VER}"
        elif [[ ${OS} == Termux ]]; then echo "termux"
        elif [[ ${OS} =~ ^Linux ]]; then echo "linux" # general linux
        else echo "unsupported"
        fi
    )
    return 0
}

check_system_package_arch() { pacman -Q "$1" >/dev/null 2>&1; }
check_system_package_debian(){ dpkg -s "$1" >/dev/null 2>&1; }

install_system_package_arch() { sudo pacman -S --needed --noconfirm "$@"; }
install_system_package_debian_7() { sudo apt-get install --yes "$@"; }
install_system_package_debian_8() { sudo apt-get install --yes "$@"; }
install_system_package_debian_9() { sudo apt-get install --yes "$@"; }
install_system_package_debian_10() { sudo apt-get install --yes "$@"; }
install_system_package_debian_11() { sudo apt-get install --yes "$@"; }
install_system_package_termux() { apt install --yes "$@"; }
install_system_package_linux() {
    # TODO: maybe flatpak?
    warning "General linux package not supported"
}

# EXPORTS ######################################################################
################################################################################

LOCAL_CONFIG_DIR="${XDG_CONFIG_HOME:-"$HOME/.config"}"
export LOCAL_CONFIG_DIR

DISTRO=$(distro)
export DISTRO
