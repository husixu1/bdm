source "$BDM_ROOT/lib/utils.sh"
source "$BDM_ROOT/lib/distro.sh"
source "$BDM_ROOT/lib/install.sh"

# $1: source location
# $2: target location
Link() { install:link_or_file "$THISDIR" "symlink" "$1" "$2" "$(id -u)" "$(id -g)" 755; }
# $1: source location
# $2: target location
LinkAsRoot() { install:link_or_file "$THISDIR" "symlink" "$1" "$2" "$(id -u root)" "$(id -g root)" 755; }
# $1: source location
# $2: target location
# $3: user
LinkAsUser() { install:link_or_file "$THISDIR" "symlink" "$1" "$2" "$(id -u "$3")" "$(id -g "$3")" 755; }

# $1: source location
# $2: target location
Copy() { install:link_or_file "$THISDIR" "file" "$1" "$2" "$(id -u)" "$(id -g)" 644; }
# $1: source location
# $2: target location
CopyAsRoot() { install:link_or_file "$THISDIR" "file" "$1" "$2" "$(id -u root)" "$(id -g root)" 644; }
# $1: source location
# $2: target location
# $3: user
CopyAsUser() { install:link_or_file "$THISDIR" "file" "$1" "$2" "$(id -u "$3")" "$(id -g "$3")" 644; }

# $1: target location
NewDir() { install:directory "$THISDIR" "$1" "$(id -u)" "$(id -g)" 755; }
# $1: target location
NewDirAsRoot() { install:directory "$THISDIR" "$1" "$(id -u root)" "$(id -g root)" 755; }
# $1: target location
# $2: user
NewDirAsUser() { install:directory "$THISDIR" "$1" "$(id -u "$2")" "$(id -g "$2")" 755; }

THISDIR=$({ cd "$(dirname "${BASH_SOURCE[0]}")" || exit; } && pwd -P)

# install wrapper
bootstrap:__install() {
    export LOG_INDENT=4
    install:transaction_start "$THISDIR"

    # do not exit when fail
    if bootstrap:install; then
        result=true
    else
        result=false
    fi
    install:transaction_commit "$THISDIR"
    unset LOG_INDENT

    $result
}

bootstrap:__uninstall() {
    export LOG_INDENT=4
    if install:purge "$THISDIR"; then
        result=true
    else
        result=false
    fi
    unset LOG_INDENT

    $result
}
