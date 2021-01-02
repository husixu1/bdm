#!/bin/bash
# shellcheck disable=SC2016

template='#!/bin/bash
eval "$(cat "$BDM_ROOT/lib/bootstrap_imports.sh")"
'"
## Dependencies ################################################################
declare -a tags=(
    support:root${NON_ROOT:+"
    support:non-root"}
    distro:arch${DEBIAN:+"
    distro:debian"}${TERMUX:+"
    distro:termux"}
)
declare -a deps

if \$ISROOT; then
    # root installation
    deps=()
    if [[ \$DISTRO == arch ]]; then
        deps+=()${DEBIAN:+"
    elif [[ DISTRO ^= debian ]]; then
        deps+=()"}${TERMUX:+"
    elif [[ DISTRO == termux ]]; then
        deps+=()"}
    fi${NON_ROOT:+"
else
    # non-root installation
    deps=()"}
fi"'

export deps tags

## Dotfiles ####################################################################
install() {
    Clean
    # Dir "$LOCAL_CONFIG_DIR/a"
    # Link "$THISDIR/a" "$LOCAL_CONFIG_DIR/a/b"
}

uninstall() {
    Purge
}
'

echo "$template"
