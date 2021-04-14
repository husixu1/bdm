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
    cat >|"$HOME/.config/bdm.conf" <<EOF
[bdm]
dotfile_dirs = $root_dir/dotfiles
usermode = false
depends = check
aur_helper_cmd = yay -S --noconfirm
cache_dir = $root_dir/cache
EOF

    # fake a some command to work around side effects
    mkdir -p "$root_dir/bin"
    cmds=(pacman apt pkg)
    for cmd in "${cmds[@]}"; do
        cat >|"$root_dir/bin/$cmd" <<EOF
#!/bin/bash
echo "SYS_PKG \$*" >> "$root_dir/fake-log"
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
    # remove all dotfiles
    rm -rf "$root_dir/dotfiles/"
    mkdir -p "$root_dir/dotfiles/"

    # remove all installed files
    rm -rf "$root_dir/dst"
    mkdir -p "$root_dir/dst"

    # remove all caches
    rm -rf "$root_dir/cache"
    mkdir -p "$root_dir/cache"

    # remove records of last run
    rm -rf ~/.config/bdm/.db

    # clear logs of fake commands
    : >|"$root_dir/fake-log"
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

    # bdm should complain about missing bootstrap:__install()
    assert "[[ \"$stderr\" == *skipping* ]]"
}

init_test_dotfile() {
    # create dotfiles config
    mkdir -p "$root_dir/dotfiles/test"
    cat >|"$root_dir/dotfiles/test/bootstrap.sh" <<EOF
#!/bin/bash
eval "\$(cat "\$BDM_LIBDIR/bootstrap_imports.sh")"
deps=(cowsay)
export deps

bootstrap:install() {
    NewDir "$root_dir/dst/dir1"
    Link "\$THISDIR/file1" "$root_dir/dst/dir1/link1"
    Copy "\$THISDIR/file2" "$root_dir/dst/dir1/copy2"
}
EOF
    echo "test file 1" >|"$root_dir/dotfiles/test/file1"
    echo "test file 2" >|"$root_dir/dotfiles/test/file2"
} 1>/dev/null

test_install_skip_deps() {
    init_test_dotfile

    # install
    bdm install --dont-hold-sudo --skip-depends test <<<$'Y\n'

    # test dotfile installation
    assert "[ -d $root_dir/dst/dir1 ]"
    assert "[ -L $root_dir/dst/dir1/link1 ]"
    assert "[ $root_dir/dst/dir1/link1 -ef $root_dir/dotfiles/test/file1 ]"
    assert "[ -f $root_dir/dst/dir1/copy2 ]"
    assert "[ -z $(diff "$root_dir/dst/dir1/copy2" "$root_dir/dotfiles/test/file2") ]"

    # test cache
} 1>/dev/null

test_install_check_deps() {
    init_test_dotfile
    stderr="$(bdm install --dont-hold-sudo --check-depends test <<<$'Y\n' 2>&1 >/dev/null)"

    # program should fail
    assert_not_equals 0 $?

    # should complain about missing dependencies
    # ($stderr is multiline, thus escaped to avoid outputting garbage)
    mapfile -t stderr_lines < <(echo "$stderr")
    assert "[[ \"${stderr_lines[0]}\" =~ missing.*cowsay ]]"
} 1>/dev/null

test_install_install_deps() {
    init_test_dotfile
    bdm install --dont-hold-sudo --install-depends test <<<$'Y\n'

    # verify that system package manager command is executed correctly
    while read -r line; do
        if [[ "$line" =~ ^SYS_PKG ]]; then
            assert "[[ \"$line\" =~ SYS_PKG.*cowsay.* ]]"
        fi
    done <"$root_dir/fake-log"
} 1>/dev/null 2>&1

test_install_dep_loop() {
    :
}

test_remove() {
    :
}
