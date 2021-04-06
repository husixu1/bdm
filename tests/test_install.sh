#!/bin/bash
source ../lib/install.sh
set -eo pipefail

setup_suite() {
    # playground directory
    root_dir="$(mktemp -d)"
    pushd "$root_dir" >/dev/null || return 1
    export root_dir

    # common config
    export db_name="test_db"
    export STORAGE_DIR="$root_dir/vars"
}

teardown_suite() {
    popd >/dev/null || return 1
    rm -r "${root_dir:?}"
}

setup() {
    echo "this is file 1" >|file1
    echo "this is file 2" >|file2
    echo "this is file 3" >|file3

    # for db testing
    declare -gA test_db=()
}

teardown() {
    rm -r "${root_dir:?}"/*
}

test_simple_transaction() {
    install:transaction_start $db_name
    install:transaction_commit
    assert "[ -f $STORAGE_DIR/$db_name ]"
}

test_link_file() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -L link1 ]"
    assert "[ link1 -ef file1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    # record content is correct
    for cmd in "${test_db[@]}"; do
        declare -A record=()
        eval "$cmd"
        assert_equals "$(realpath file1)" "${record[source]}"
        assert_equals "$(realpath -s link1)" "${record[target]}"
        assert_equals "symlink" "${record[hash]}"
    done
} 1>/dev/null

test_copy_file() {
    install:transaction_start "$db_name"
    install:link_or_file file file1 file1_copy "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -f file1_copy ]"
    assert "[ -z $(diff file1 file1_copy) ]"
    assert "[ $(stat -c "%a" file1_copy) -eq 755 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    # record content is correct
    for cmd in "${test_db[@]}"; do
        declare -A record=()
        eval "$cmd"
        assert_equals "$(realpath file1)" "${record[source]}"
        assert_equals "$(realpath file1_copy)" "${record[target]}"
        assert_equals "$(install:hash_file file1)" "${record[hash]}"
        assert_equals 755 "${record[permission]}"
    done
} 1>/dev/null

test_install_directory() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # dir correctly installed
    assert "[ -d dir1 ]"
    assert "[ $(stat -c "%a" dir1) -eq 755 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    # record content is correct
    for cmd in "${test_db[@]}"; do
        declare -A record=()
        eval "$cmd"
        assert_equals "" "${record[source]}"
        assert_equals "$(realpath dir1)" "${record[target]}"
        assert_equals "directory" "${record[hash]}"
        assert_equals 755 "${record[permission]}"
    done
} 1>/dev/null

test_remove_file_within_transaction() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:remove_link_or_file symlink file1 link1
    install:transaction_commit

    # file correctly removed
    assert_fail "[ -L link1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_remove_file_across_trnsaction() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 link1
    install:transaction_commit

    # file correctly removed
    assert_fail "[ -L link1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_remove_directory_within_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:remove_directory dir1
    install:transaction_commit

    # dir correctly removed
    assert_fail "[ -d dir1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_remove_directory_across_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    install:transaction_start "$db_name"
    install:remove_directory dir1
    install:transaction_commit

    # dir correctly removed
    assert_fail "[ -d dir1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_clean() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:link_or_file symlink file1 dir1/link1 "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 dir1/file2 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 3 "${#test_db[@]}"

    # remove one file and clean db
    rm file1
    install:clean "$db_name"
    # link removed
    assert_fail "[ -L dir1/link1 ]"
    # record removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 2 "${#test_db[@]}"

    # remove all targets and clean db
    rm file2
    install:clean "$db_name"
    # file removed
    assert_fail "[ -f dir1/file2 ]"
    # record removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"
} 1>/dev/null

test_purge() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:link_or_file symlink file1 dir1/link1 "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 dir1/file2 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # targets installed
    assert "[[ -L dir1/link1 && dir1/link1 -ef file1 ]]"
    assert "[ -f dir1/file2 ]"
    assert_equals "$(install:hash_file dir1/file2)" "$(install:hash_file file2)"
    assert "[ -d dir1 ]"

    # recorded correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 3 "${#test_db[@]}"

    install:transaction_start "$db_name"
    install:purge
    install:transaction_commit

    # targets removed
    assert_fail "[ -L dir1/link1 ]"
    assert_fail "[ -f dir1/file2 ]"
    assert_fail "[ -d dir1 ]"

    # record removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

