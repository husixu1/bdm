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
declare -a opts=()

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
bootstrap:install() {
    Clean
    # NewDir "$LOCAL_CONFIG_DIR/a"
    # Link "$THISDIR/a" "$LOCAL_CONFIG_DIR/a/b"
    # Copy "$THISDIR/a" "$LOCAL_CONFIG_DIR/a/b"
}
'

echo "$template"
