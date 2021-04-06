source "$BDM_ROOT/lib/utils.sh"
source "$BDM_ROOT/lib/distro.sh"
source "$BDM_ROOT/lib/install.sh"

# $1: source location
# $2: target location
Link() { install:link_or_file "symlink" "$1" "$2" "$(id -u)" "$(id -g)" 755; }
# $1: source location
# $2: target location
LinkAsRoot() { install:link_or_file "symlink" "$1" "$2" "$(id -u root)" "$(id -g root)" 755; }
# $1: source location
# $2: target location
# $3: user
LinkAsUser() { install:link_or_file "symlink" "$1" "$2" "$(id -u "$3")" "$(id -g "$3")" 755; }

# $1: source location
# $2: target location
Copy() { install:link_or_file "file" "$1" "$2" "$(id -u)" "$(id -g)" 644; }
# $1: source location
# $2: target location
CopyAsRoot() { install:link_or_file "file" "$1" "$2" "$(id -u root)" "$(id -g root)" 644; }
# $1: source location
# $2: target location
# $3: user
CopyAsUser() { install:link_or_file "file" "$1" "$2" "$(id -u "$3")" "$(id -g "$3")" 644; }

# $1: target location
NewDir() { install:directory "$1" "$(id -u)" "$(id -g)" 755; }
# $1: target location
NewDirAsRoot() { install:directory "$1" "$(id -u root)" "$(id -g root)" 755; }
# $1: target location
# $2: user
NewDirAsUser() { install:directory "$1" "$(id -u "$2")" "$(id -g "$2")" 755; }

THISDIR=$({ cd "$(dirname "${BASH_SOURCE[0]}")" || exit; } && pwd -P)

# install wrapper
bootstrap:__install() {
    export LOG_INDENT=4
    install:transaction_start "$THISDIR.db"
    # don't exit when fail
    if bootstrap:install; then
        result=true
    else
        result=false
    fi
    # purge old db
    install:purge
    install:transaction_commit
    unset LOG_INDENT

    $result
}

bootstrap:__uninstall() {
    export LOG_INDENT=4
    install:transaction_start "$THISDIR.db"
    if install:purge; then
        result=true
    else
        result=false
    fi
    install:transaction_commit
    unset LOG_INDENT

    $result
}
