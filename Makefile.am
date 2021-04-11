pkgtemplatesdir = $(pkglibexecdir)/templates

dist_bin_SCRIPTS = bdm

dist_pkglibexec_SCRIPTS =   \
							lib/distro.sh              \
							lib/install.sh             \
							lib/read_ini.sh            \
							lib/utils.sh               \
							lib/bootstrap_imports.sh

dist_pkgtemplates_SCRIPTS = \
							templates/zsh_path.sh      \
							templates/fish_path.sh     \
							templates/bash_path.sh     \
							templates/gen_bootstrap.sh

sysconf_DATA = bdm.conf

bdm: bdm.template
	sed -e 's,@BDM_CONFDIR\@,$(sysconfdir),g' \
		-e 's,@BDM_LIBDIR\@,$(pkglibexecdir),g' \
		$^ > $@

CLEANFILES = ${dist_bin_SCRIPTS}
