source "$BDM_ROOT/lib/utils.sh"
source "$BDM_ROOT/lib/distro.sh"
source "$BDM_ROOT/lib/install.sh"

Link() { installSymLink "$THISDIR" "$@"; }
Dir() { installDirectory "$THISDIR" "$@"; }
Purge() { purge "$THISDIR"; }
Clean() { clean "$THISDIR"; }

THISDIR=$({ cd "$(dirname "${BASH_SOURCE[0]}")" || exit; } && pwd -P)
