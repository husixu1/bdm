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

dist_sysconf_DATA = bdm.conf

bdm: bdm.template
	sed -e 's,@BDM_CONFDIR\@,$(sysconfdir),g' \
		-e 's,@BDM_LIBDIR\@,$(pkglibexecdir),g' \
		-e 's,@BDM_VERSION\@,$(BDM_VERSION),g' \
		$^ > $@

if FOUND_A2X
dist_man1_MANS = man/BDM.1
$(dist_man1_MANS): man/bdm.adoc
	a2x --doctype manpage --format manpage $^
endif

CLEANFILES = ${dist_bin_SCRIPTS} ${dist_man1_MANS}
