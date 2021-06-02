#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

# BDM version number
m4_define([bdm_VERSION], [0.2])

AC_PREREQ([2.71])
AC_INIT([bdm], m4_defn([bdm_VERSION]), [husixu1 . at . hotmail.com])
AM_INIT_AUTOMAKE([foreign])
AC_CONFIG_SRCDIR([bdm.template])

# Checks for programs.
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET

# Pass version number to makefile
AC_SUBST([BDM_VERSION], m4_defn([bdm_VERSION]))

# Check for doc generating tool
AC_CHECK_PROG([found_a2x], [a2x], [yes])
AM_CONDITIONAL([FOUND_A2X], [test x"$found_a2x" = x"yes"])
AM_COND_IF([FOUND_A2X],,[AC_CONFIG_COMMANDS([default],
           [echo; echo "WARNING: Command 'a2x' not found, installation can `
            `still proceed but man pages will not be installed. Install `
            `asciidoc and reconfigure to fix this problem."])])

AC_CONFIG_FILES([
    Makefile
])

AC_OUTPUT
