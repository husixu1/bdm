#!/bin/bash
# This file contains some spaghetti code to unit-test the install.sh library

# shellcheck source=../lib/install.sh
source /usr/local/libexec/bdm/install.sh
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
    assert_equals 0 $?
    assert "[ -f $STORAGE_DIR/$db_name ]"
}

# test whether soft linking works
test_install_link_file() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -L link1 ]"
    assert "[ link1 -ef file1 ]"

    # record correctly added to db
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

# test whether file copy works
test_install_copy_file() {
    install:transaction_start "$db_name"
    install:link_or_file file file1 file1_copy "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -f file1_copy ]"
    assert "[ -z $(diff file1 file1_copy) ]"
    assert "[ $(stat -c "%a" file1_copy) -eq 755 ]"

    # record correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    # record content is correct
    for cmd in "${test_db[@]}"; do
        declare -A record=()
        echo "$cmd"
        eval "$cmd"
        assert_equals "$(realpath file1)" "${record[source]}"
        assert_equals "$(realpath file1_copy)" "${record[target]}"
        assert_equals "$(install:hash_file file1)" "${record[hash]}"
        assert_equals 755 "${record[permission]}"
    done
} 1>/dev/null

# same target cannot be installed twice
test_install_twice_within_transaction_1() {
    install:transaction_start "$db_name"

    # two same installation with same source and destination
    # can't happen in the same transaction
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    assert_equals 0 $?
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 644
    assert_not_equals 0 $?
} >/dev/null 2>&1

# same target cannot be installed twice, even with different type
test_install_twice_within_transaction_2() {
    install:transaction_start "$db_name"

    # two same installation with same source and destination
    # can't happen in the same transaction
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    assert_equals 0 $?
    install:link_or_file copy file1 file1_link "$(id -u)" "$(id -g)" 644
    assert_not_equals 0 $?
} >/dev/null 2>&1

# same target cannot be installed twice, even with different source
test_install_twice_within_transaction_3() {
    install:transaction_start "$db_name"

    # two same installation with same source and destination
    # can't happen in the same transaction
    install:link_or_file symlink file1 file_link "$(id -u)" "$(id -g)" 755
    assert_equals 0 $?
    install:link_or_file symlink file2 file_link "$(id -u)" "$(id -g)" 755
    assert_not_equals 0 $?
} >/dev/null 2>&1

# if the same source -> target intalled in different transaction,
# file and db should remain unchanged
test_install_link_twice_across_transaction() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -L file1_link ]"
    assert "[ file1_link -ef file1 ]"

    # record correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    value_arr=("${test_db[@]}")
    old_rec="${value_arr[0]}"

    # change content and install again
    echo "some spice" >>file1
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file remains the same
    assert "[ -L file1_link ]"
    assert "[ file1_link -ef file1 ]"

    # db is not changed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    value_arr=("${test_db[@]}")
    new_rec="${value_arr[0]}"
    assert_equals "$old_rec" "$new_rec"
} 1>/dev/null

# if content of source file changed, it should be correctly propagated to
# destination file
test_install_file_twice_across_transaction() {
    install:transaction_start "$db_name"
    install:link_or_file file file1 file1_copy "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -f file1_copy ]"
    assert "[ -z '$(diff file1_copy file1)' ]"

    # change content and install again
    echo "some spice" >>file1
    install:transaction_start "$db_name"
    install:link_or_file file file1 file1_copy "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file remains the same
    assert "[ -f file1_copy ]"
    assert "[ -z '$(diff file1_copy file1)' ]"

    # db is not changed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"
} 1>/dev/null

# foreign file removal to installed file should not break next installation
test_install_resilience_to_foreign_remove() {
    # link file1 -> file_link
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file_link "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -L file_link ]"

    # make foreign change 1
    #######################
    unlink file_link

    # link file1 -> file_link again
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file_link "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # new link correctly installed
    assert "[ -L file_link ]"
    assert "[ file_link -ef file1 ]"

    # db is not affected by foreign changes
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    declare -A record=()
    value_arr=("${test_db[@]}")
    eval "${value_arr[0]}"
    assert_equals "$(realpath file1)" "${record[source]}"

    # make foreign change 2
    #######################
    unlink file_link

    # link file2 -> file_link
    install:transaction_start "$db_name"
    install:link_or_file symlink file2 file_link "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # new link correctly installed
    assert "[ -L file_link ]"
    assert "[ file_link -ef file2 ]"

    # db is not affected by foreign changes
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"

    declare -A record=()
    value_arr=("${test_db[@]}")
    eval "${value_arr[0]}"
    assert_equals "$(realpath file2)" "${record[source]}"
} 1>/dev/null 2>&1

# foreign file modification to installed file should not break next installation
test_install_resilience_to_foreign_modification() {
    # copy file1 -> file_copy
    install:transaction_start "$db_name"
    install:link_or_file file file1 file_copy "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # file correctly installed
    assert "[ -f file_copy ]"
    assert "[ -z '$(diff file1 file_copy)' ]"

    db:load "$STORAGE_DIR/$db_name" test_db
    old_db="$(declare -p test_db)"

    # make foreign change 1
    #######################
    echo "some modifications" >>file_copy

    # copy file1 -> file_copy again
    install:transaction_start "$db_name"
    stderr=$(install:link_or_file file file1 file_copy "$(id -u)" "$(id -g)" 755 2>&1 >/dev/null)

    # this should fail, since foreign changes are made, and we should not
    # overwrite user's change.
    assert_not_equals 0 $?

    # the program should complain that the target file is no longer managed
    mapfile -t stderr_lines < <(echo "$stderr")
    assert "[[ \"${stderr_lines[0]}\" == *\"no longer managed\"* ]]"

    # commit the changes
    install:transaction_commit
    new_db="$(declare -p test_db)"

    # db should remain unchanged after commit
    assert "[ -z $(diff <(echo "$old_db") <(echo "$new_db")) ]"
} 1>/dev/null

# installation on a existing file that is not inside the db should fail
test_install_over_foreign_file() {
    echo "this is an existing file" >>file_copy

    # copy file1 -> file_copy again
    install:transaction_start "$db_name"
    stderr=$(install:link_or_file file file1 file_copy "$(id -u)" "$(id -g)" 755 2>&1 >/dev/null)

    # this should fail, since foreign changes are made, and we should not
    # overwrite user's change.
    assert_not_equals 0 $?

    # the program should complain that the target file is no longer managed
    mapfile -t stderr_lines < <(echo "$stderr")
    assert "[[ \"${stderr_lines[0]}\" == *\"not managed\"* ]]"
}

# if db accidentally removed, existing installation
# should not be affected in the next round
test_install_resilience_to_db_removal() {
    # do a base installation
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 file2_copy "$(id -u)" "$(id -g)" 644
    install:transaction_commit

    # file correctly installed
    assert "[ -L file1_link ]"
    assert "[ file1_link -ef file1 ]"
    assert "[ -f file2_copy ]"
    assert "[ -z '$(diff file2_copy file2)' ]"

    # remove db
    rm "$STORAGE_DIR/$db_name"
    assert_fail "[ -f $STORAGE_DIR/$db_name ]"

    # install again
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 file1_link "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 file2_copy "$(id -u)" "$(id -g)" 644
    install:transaction_commit

    # file still correctly installed
    assert "[ -L file1_link ]"
    assert "[ file1_link -ef file1 ]"
    assert "[ -f file2_copy ]"
    assert "[ -z '$(diff file2_copy file2)' ]"

    # new records correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 2 "${#test_db[@]}"
} >/dev/null 2>&1

test_install_directory() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # dir correctly installed
    assert "[ -d dir1 ]"
    assert "[ $(stat -c "%a" dir1) -eq 755 ]"

    # record correctly added to db
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

# install the same directory twice with the same should fail
test_install_dir_twice_within_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    assert_equals 0 $?
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    assert_not_equals 0 $?
} 1>/dev/null 2>&1

test_install_dir_twice_across_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # directory installed correctly
    assert "[ -d dir1 ]"

    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # directory installed correctly
    assert "[ -d dir1 ]"

    # db still only has 1 record
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 1 "${#test_db[@]}"
} 1>/dev/null

test_remove_file_within_transaction() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:remove_link_or_file symlink file1 link1
    install:transaction_commit

    # file correctly removed
    assert_fail "[ -L link1 ]"

    # record correctly added to db
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_remove_file_across_transction() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 link1
    install:transaction_commit

    # file correctly removed
    assert_fail "[ -L link1 ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

# if file is removed by user, subsequent removal by bdm should still work
test_remove_file_resilience_to_foreign_remove() {
    install:transaction_start "$db_name"
    install:link_or_file symlink file1 link1 "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 copy2 "$(id -u)" "$(id -g)" 755
    install:link_or_file symlink file2 link2 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # manual removal
    rm copy2
    unlink link1
    unlink link2

    # verify removal
    assert_fail "[ -L link1 ]"
    assert_fail "[ -f copy2 ]"
    assert_fail "[ -L link2 ]"

    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 link1
    assert_equals 0 $?
    install:remove_link_or_file file file2 copy2
    assert_equals 0 $?
    install:remove_link_or_file file file2 link2
    assert_equals 0 $?
    install:transaction_commit

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

# if file is changed by user, subsequent removal by bdm should only remove
# records in db, as we should not always respect user's change
test_remove_file_resilience_to_foreign_change() {
    install:transaction_start "$db_name"
    install:link_or_file file file1 copy1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # change file content
    echo "some spice" >>copy1
    old_content="$(cat copy1)"

    # remove the installation
    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 copy1
    install:transaction_commit

    # file remains unchanged
    assert "[ -z $(diff <(echo "$old_content") copy1) ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

# foreign file should not be removed
test_remove_foreign_file() {
    # change file content
    echo "some spice" >>copy1
    old_content="$(cat copy1)"

    # remove the installation
    install:transaction_start "$db_name"
    stderr="$(install:remove_link_or_file symlink file1 copy1 2>&1 >/dev/null)"
    # function call should return success
    assert_equals 0 $?
    install:transaction_commit

    assert "[ -n \"$stderr\" ]"
    mapfile -t stderr_lines < <(echo "$stderr")
    assert "[[ \"${stderr_lines[0]}\" == *skipping* ]]"
}

# if db accidentally removed, removal should not be affected in the next round
test_remove_file_resilience_to_db_removal() {
    install:transaction_start "$db_name"
    install:link_or_file file file1 copy1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # remove db
    rm "$STORAGE_DIR/$db_name"
    assert_fail "[ -f $STORAGE_DIR/$db_name ]"

    # remove the installation
    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 copy1
    assert_equals 0 $?
    install:transaction_commit

    # file removed
    assert_fail "[ -f copy1 ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

# non-existing file should just be skipped
test_remove_non_existing_file(){
    # remove the installation
    install:transaction_start "$db_name"
    install:remove_link_or_file symlink file1 some_copy
    assert_equals 0 $?
    install:transaction_commit
} 1>/dev/null 2>&1

test_remove_directory_within_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:remove_directory dir1
    install:transaction_commit

    # dir correctly removed
    assert_fail "[ -d dir1 ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

test_remove_directory_across_transaction() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    install:transaction_start "$db_name"
    install:remove_directory dir1
    assert_equals 0 $?
    install:transaction_commit

    # dir correctly removed
    assert_fail "[ -d dir1 ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null

# if directory is remove by user, subsequent removal should still succeed
test_remove_dir_resilience_to_foreign_remove() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # remove directory manually
    rm -r dir1
    assert_fail "[ -d dir1 ]"

    install:transaction_start "$db_name"
    install:remove_directory dir1
    assert_equals 0 $?
    install:transaction_commit

    # dir correctly removed
    assert_fail "[ -d dir1 ]"

    # record correctly removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

# remove foreign directory should always succeess, in the directory case,
# it is equvalent to `resistance_to_db_removal`, since the foreign dir is
# not recorded in the db.
test_remove_foreign_directory(){
    # create the directory
    mkdir dir1
    assert "[ -d dir1 ]"

    install:transaction_start "$db_name"
    install:remove_directory dir1
    assert_equals 0 $?
    install:transaction_commit

    # record removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

# this should just skip
test_remove_non_existing_directory(){
    install:transaction_start "$db_name"
    install:remove_directory some_dir
    assert_equals 0 $?
    install:transaction_commit

    # record removed
    db:load "$STORAGE_DIR/$db_name" test_db
    assert_equals 0 "${#test_db[@]}"
} 1>/dev/null 2>&1

test_clean() {
    install:transaction_start "$db_name"
    install:directory dir1 "$(id -u)" "$(id -g)" 755
    install:link_or_file symlink file1 dir1/link1 "$(id -u)" "$(id -g)" 755
    install:link_or_file file file2 dir1/file2 "$(id -u)" "$(id -g)" 755
    install:transaction_commit

    # record correctly added to db
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

    # record correctly added to db
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
