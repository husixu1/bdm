source "$BDM_ROOT/lib/utils.sh"
source "$BDM_ROOT/lib/distro.sh"
source "$BDM_ROOT/lib/install.sh"

Link() { installSymLink "$THISDIR" "$@"; }
Dir() { install_directory "$THISDIR" "$@"; }

THISDIR=$({ cd "$(dirname "${BASH_SOURCE[0]}")" || exit; } && pwd -P)

# install wrapper
__install() {
    export LOG_INDENT=4
    transaction_start
    install
    transaction_commit
    unset LOG_INDENT
}

__uninstall() {
    export LOG_INDENT=4
    purge "$THISDIR";
    unset LOG_INDENT
}
