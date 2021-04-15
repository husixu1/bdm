#!/bin/bash
# shellcheck disable=SC2034

# This file contains integration tests. They should be executed after bdm is
# installed, and it should be exected in an isolated environment (e.g. docker)
# to avoid pollution.

setup_suite() {
    # playground directory
    root_dir="$(mktemp -d)"
    pushd "$root_dir" >/dev/null || return 1
    export root_dir

    # basic config
    mkdir -p "$HOME/.config"
    cat >|"$HOME/.config/bdm.conf" <<-EOF
		[bdm]
		dotfile_dirs = $root_dir/dotfiles
		usermode = false
		depends = check
		aur_helper_cmd = yay -S --noconfirm
		cache_dir = $root_dir/cache
	EOF

    # fake a some command to work around side effects
    mkdir -p "$root_dir/bin"
    cmds=(pacman yay apt pkg yum)
    for cmd in "${cmds[@]}"; do
        cat >|"$root_dir/bin/$cmd" <<-EOF
		    #!/bin/bash
		    echo "SYS_PKG \$*" >> "$root_dir/dep-install-log"
		EOF
        chmod +x "$root_dir/bin/$cmd"
    done
    export PATH="$root_dir/bin:$PATH"

} 1>/dev/null

teardown_suite() {
    popd >/dev/null || return 1
    rm -r "${root_dir:?}"
}

setup() {
    # clean dirs
    dirs_to_clean=(dotfiles dst cache deps)
    for dir in "${dirs_to_clean[@]}"; do
        rm -rf "${root_dir:?}/$dir/"
        mkdir -p "$root_dir/$dir/"
    done

    # remove records of last run
    rm -rf ~/.config/bdm/.db

    # clear logs of fake commands
    : >|"$root_dir/dep-install-log"
}

teardown() {
    :
}

###############################################################################

test_new_dotfile() {
    bdm new test <<<"1"
    assert "[ -d $root_dir/dotfiles/test ]"
    assert "[ -f $root_dir/dotfiles/test/bootstrap.sh ]"
} 1>/dev/null

test_intall_empty_dotfile() {
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<<"#!/bin/bash"

    stderr="$(bdm install --dont-hold-sudo test <<<$'Y\n' 2>&1 >/dev/null)"
    assert_equals 0 $?

    [[ "${stderr,,}" == *skipping* ]] ||
        fail "should complain about missing bootstrap:__install()"
}

# installation of invalid dotfiles should fail
test_install_invalid_dotfile() {
    mkdir -p "$root_dir/dotfiles/test"

    # create a false dotfile
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<-EOF
		#!/bin/bash
		exit 1
	EOF

    stderr="$(bdm install --dont-hold-sudo --skip-depends test <<<$'Y\n' 2>&1 >/dev/null)"
    assert_not_equals 0 $?

    [[ "${stderr,,}" == *failed* ]] ||
        fail "should warn the installation failure"
} 1>/dev/null

__init_test_dotfile() {
    # create dotfiles config
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(
		    cowsay
		    ctags::aur:ctags
		    fi:file1::f:installfile1
		    e:exe1::f:installexe1
		    fu:dep_check1::f:dep_func1
		)
		tags=(tag1 tag2)
		export deps tags

		installfile1() {
		    echo "install file 1" >| $root_dir/deps/file1
		}
		installexe1() {
		    echo "install exe 1" >| $root_dir/deps/exe1
		    chmod +x $root_dir/deps/exe1
		}
		dep_check1() { false; }
		dep_func1() {
		    echo "execute func 1" >| $root_dir/deps/func1-log
		}

		bootstrap:install() {
		    NewDir "$root_dir/dst/dir1"
		    Link "\$THISDIR/file1" "$root_dir/dst/dir1/link1"
		    Copy "\$THISDIR/file2" "$root_dir/dst/dir1/copy2"
		}
	EOF

    echo "test file 1" >|"$root_dir/dotfiles/test/file1"
    echo "test file 2" >|"$root_dir/dotfiles/test/file2"
} 1>/dev/null 2>&1

test_install_skip_deps() {
    __init_test_dotfile

    # install
    bdm install --dont-hold-sudo --skip-depends test <<<$'Y\n'
    assert_equals 0 $?

    # test dotfile installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -L $root_dir/dst/dir1/link1 ]"
    assert "[ $root_dir/dst/dir1/link1 -ef $root_dir/dotfiles/test/file1 ]"
    assert "[ -f $root_dir/dst/dir1/copy2 ]"
    assert "[ -z $(diff "$root_dir/dst/dir1/copy2" "$root_dir/dotfiles/test/file2") ]"

    # no dependencies should be installed
    assert "[ -z \"$(cat dep-install-log)\" ]"
} 1>/dev/null

test_install_check_deps() {
    __init_test_dotfile
    stderr="$(bdm install --dont-hold-sudo --check-depends test <<<$'Y\n' 2>&1 >/dev/null)"
    # program should fail
    assert_not_equals 0 $?

    [[ "${stderr//$'\n'/ }" =~ missing.*cowsay ]] ||
        fail "should complain about missing dependencies"
} # 1>/dev/null

test_install_install_deps() {
    __init_test_dotfile
    bdm install --dont-hold-sudo --install-depends test <<<$'Y\n'
    assert_equals 0 $?

    # test dotfile installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -L $root_dir/dst/dir1/link1 ]"
    assert "[ $root_dir/dst/dir1/link1 -ef $root_dir/dotfiles/test/file1 ]"
    assert "[ -f $root_dir/dst/dir1/copy2 ]"
    assert "[ -z $(diff "$root_dir/dst/dir1/copy2" "$root_dir/dotfiles/test/file2") ]"

    # verify that system package manager command is executed correctly
    mapfile -t lines <"$root_dir/dep-install-log"
    assert_equals 2 "${#lines[@]}"
    assert "[[ \"${lines[0]}\" =~ SYS_PKG.*cowsay.* ]]"
    assert "[[ \"${lines[1]}\" =~ SYS_PKG.*ctags.* ]]"

    # verify other dependencies
    assert "[ -f $root_dir/deps/file1 ]"
    assert "[ '$(cat "$root_dir/deps/file1")' == 'install file 1' ]"
    assert "[ -x $root_dir/deps/exe1 ]"
    assert "[ '$(cat "$root_dir/deps/exe1")' == 'install exe 1' ]"
    assert "[ -f $root_dir/deps/func1-log ]"
    assert "[ '$(cat "$root_dir/deps/func1-log")' == 'execute func 1' ]"

} 1>/dev/null 2>&1

test_install_invalid_deps_1() {
    # create dotfiles with invalid dependency
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(asdf:file1); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir"; }
	EOF

    stderr="$(bdm install --dont-hold-sudo --install-depends test <<<$'Y\n' 2>&1 >/dev/null)"
    assert_not_equals 0 $?

    # bootstrap:install() should not be executed
    assert_fail "[ -d $root_dir/dst/dir ]"

    [[ "${stderr//$'\n'/ }" == *"unrecognized"* ]] ||
        fail "should warn about the unknown dependency type"
} 1>/dev/null

test_install_invalid_deps_2() {
    # create dotfiles with invalid dependency
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(fi:file1); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir"; }
	EOF

    stderr="$(bdm install --dont-hold-sudo --install-depends test <<<$'Y\n' 2>&1 >/dev/null)"
    assert_not_equals 0 $?

    # bootstrap:install() should not be executed
    assert_fail "[ -d $root_dir/dst/dir ]"

    [[ "${stderr//$'\n'/ }" == *"unspecified"* ]] ||
        fail "should warn about the unspecified installation method"
} 1>/dev/null

test_install_invalid_deps_3() {
    # create dotfiles with invalid dependency
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(d:non_existing_dotfile); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir"; }
	EOF

    stderr="$(bdm install --dont-hold-sudo --install-depends test <<<$'Y\n' 2>&1 >/dev/null)"
    assert_not_equals 0 $?

    # bootstrap:install() should not be executed
    assert_fail "[ -d $root_dir/dst/dir ]"

    [[ "${stderr//$'\n'/ }" == *"not exist"* ]] ||
        fail "should warn about the non-existing dotfile"
} 1>/dev/null

test_install_dep_loop() {
    # create a test1 -> test2 -> test3 dependency loop
    mkdir -p "$root_dir/dotfiles/"test{1,2,3}
    cat >|"$root_dir/dotfiles/test1/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(d:test2); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir1"; }
	EOF

    cat >|"$root_dir/dotfiles/test2/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(d:test3); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir2"; }
	EOF

    cat >|"$root_dir/dotfiles/test3/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(d:test1); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir3"; }
	EOF

    stderr="$(bdm install --dont-hold-sudo --install-depends test1 <<<$'Y\n' 2>&1 >/dev/null)"
    assert_not_equals 0 $?

    # bootstrap:install() should not be executed
    assert_fail "[ -d $root_dir/dst/dir1 ]"
    assert_fail "[ -d $root_dir/dst/dir2 ]"
    assert_fail "[ -d $root_dir/dst/dir3 ]"

    # check error messages
    stderr="${stderr//$'\n'/ }"
    [[ "${stderr,,}" == *"dependency loop"* ]] ||
        fail "should warn about the dependency loop"
} 1>/dev/null

test_install_with_tags() {
    __init_test_dotfile

    # install
    bdm install --dont-hold-sudo --skip-depends t:tag2 <<<$'Y\n'
    assert_equals 0 $?

    # test dotfile installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -L $root_dir/dst/dir1/link1 ]"
    assert "[ $root_dir/dst/dir1/link1 -ef $root_dir/dotfiles/test/file1 ]"
    assert "[ -f $root_dir/dst/dir1/copy2 ]"
    assert "[ -z $(diff "$root_dir/dst/dir1/copy2" "$root_dir/dotfiles/test/file2") ]"
} 1>/dev/null

test_post_install_func() {
    # create a test1 -> test2 -> test3 dependency loop
    mkdir -p "$root_dir/dotfiles/"test{1,2}
    cat >|"$root_dir/dotfiles/test1/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(d:test2); export deps
		bootstrap:install() {
			NewDir "$root_dir/dst/dir1"
			if [[ -n \$POST_INSTALL_EXECUTED ]]; then
				echo "affected by post-install" >| "$root_dir/dst/post-install-file1"
			fi
		}
	EOF

    cat >|"$root_dir/dotfiles/test2/bootstrap.sh" <<-EOF
		#!/bin/bash
		eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
		deps=(); export deps
		bootstrap:install() { NewDir "$root_dir/dst/dir2"; }
		bootstrap:post_install() {
			echo "post install" >| $root_dir/dst/post-install-file2
			export POST_INSTALL_EXECUTED=1
		}
	EOF

    # install
    bdm install --dont-hold-sudo --install-depends test1 <<<$'Y\n'
    assert_equals 0 $?

    # check installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -d $root_dir/dst/dir2 ]"

    # post-install function executed
    assert "[ -f $root_dir/dst/post-install-file2 ]"
    assert_equals "post install" "$(cat "$root_dir/dst/post-install-file2")"

    # post-install function can affect subsequent installation
    assert "[ -f $root_dir/dst/post-install-file1 ]"
    assert_equals "affected by post-install" "$(cat "$root_dir/dst/post-install-file1")"
} 1>/dev/null

test_uninstall() {
    __init_test_dotfile

    bdm install --dont-hold-sudo --install-depends test <<<$'Y\n'
    assert_equals 0 $?

    # test dotfile installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -L $root_dir/dst/dir1/link1 ]"
    assert "[ $root_dir/dst/dir1/link1 -ef $root_dir/dotfiles/test/file1 ]"
    assert "[ -f $root_dir/dst/dir1/copy2 ]"
    assert "[ -z $(diff "$root_dir/dst/dir1/copy2" "$root_dir/dotfiles/test/file2") ]"

    bdm uninstall test
    assert_equals 0 $?

    # verify dotfiles are removed
    assert_fail "[ -d $root_dir/dst/dir1 ]"
    assert_fail "[ -L $root_dir/dst/dir1/link1 ]"
    assert_fail "[ -f $root_dir/dst/dir1/copy2 ]"
} 1>/dev/null 2>&1

test_search() {
    __init_test_dotfile

    output="$(bdm search test)"
    assert_equals 0 $?

    [[ "${output//$'\n'/ }" == *test* ]] ||
        fail "search should output name of the dotfile"
} 1>/dev/null

test_search_by_tag() {
    __init_test_dotfile

    output="$(bdm search tag2)"
    assert_equals 0 $?

    [[ "${output//$'\n'/ }" == *test* ]] ||
        fail "search should output name of the dotfile"
} 1>/dev/null

test_search_details() {
    :
}

test_list_nothing() {
    __init_test_dotfile

    # list dotfiles
    output="$(bdm list tag2)"
    assert_equals 0 $?

    # if nothing is installed, should output nothing
    [[ -z "${output}" ]] || fail "should output nothing"
}

test_list_installed_file() {
    __init_test_dotfile

    # install dotfile
    bdm install --dont-hold-sudo --install-depends test <<<$'Y\n'
    assert_equals 0 $?

    # list dotfiles
    output="$(bdm list tag2)"
    assert_equals 0 $?

    # if nothing is installed, should output nothing
    [[ "${output//$'\n'/ }" == *test* ]] ||
        fail "should output intalled dotfile"
} 1>/dev/null 2>&1

test_list_details() {
    __init_test_dotfile

    # install dotfile
    bdm install --dont-hold-sudo --install-depends test <<<$'Y\n'
    assert_equals 0 $?

    # list dotfiles
    output="$(bdm list --files test)"
    assert_equals 0 $?

    # if nothing is installed, should output nothing
    [[ "${output//$'\n'/ }" == *test* ]] || fail "should output intalled dotfile"
    [[ "${output//$'\n'/ }" == *dir1* ]] || fail "should output intalled dirs"
    [[ "${output//$'\n'/ }" == *link1* ]] || fail "should output intalled dirs"
    [[ "${output//$'\n'/ }" == *copy2* ]] || fail "should output intalled dirs"
} 1>/dev/null 2>&1
