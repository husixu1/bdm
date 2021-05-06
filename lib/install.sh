#!/bin/bash
if [[ -n $__DEFINED_INSTALL_SH ]]; then return; fi
declare __DEFINED_INSTALL_SH=1

#shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")"/utils.sh

## Transaction functions #######################################################

# Before executing the `install*/purge/clean` commands, `transaction_start`
# should be called to properly clean the residue of last installlation.
#
# When all installaAtion is done, `transaction_commit` should be executed to
# save the entries to $STORAGE_DIR/<bootstrap-dir-name> file

# $1: dotfile directory
declare db_file
install:transaction_start() {
    db_file="$STORAGE_DIR/$(basename "$1")"
    db:load /dev/null tmp_db
    if [[ -f $db_file ]]; then
        db:load "$db_file" db
    else
        db:load /dev/null db
    fi
}

# $1: commit current db
install:transaction_commit() {
    db:save "$db_file" tmp_db
}

## Install/Uninstall functions #################################################

# $1: installation type ('symlink' for soft linking, 'file' for file copy)
# $2: source file
# $3: target location
# $4: uid
# $5: gid
# $6: permission
# return: 0|1: caller should return this value, 2: caller should continue
install:link_or_file() {
    local src tgt uid gid perm old_records
    install_type="$1"
    src="$(realpath "$2")"
    tgt="$(realpath -ms "$3")"
    uid="$(id -u "$4")"
    gid="$(id -g "$5")"
    perm="$6"

    if ! [[ -e $src ]]; then
        log:error "$src does not exist"
        return 1
    fi

    if [[ $install_type == "symlink" ]]; then
        __add_new_record() {
            local -A record=(
                [id]="" [source]="$src" [target]="$tgt"
                [uid]="$uid" [gid]="$gid" [hash]="symlink"
                [permission]="$perm"
            )
            install:db_add_record tmp_db record
        }
    elif [[ $install_type == "file" ]]; then
        __add_new_record() {
            local -A record=(
                [id]="" [source]="$src" [target]="$tgt"
                [uid]="$uid" [gid]="$gid" [hash]="$(install:hash_file "$tgt")"
                [permission]="$perm"
            )
            install:db_add_record tmp_db record
        }
    else
        log:error "Unknown installation type '$install_type'"
        return 1
    fi

    # skip if already installed as new target
    filter_new() {
        local -n rec="$1"
        [[ ${rec[target]} == "$tgt" ]]
    }
    new_records="$(install:db_find_records tmp_db filter_new)"
    if [[ -n "$new_records" ]]; then
        log:error "... --> $tgt can only be installed once in a transaction."
        return 1
    fi

    filter_old() {
        local -n rec="$1"
        [[ ${rec[source]} == "$src" && ${rec[target]} == "$tgt" ]]
    }
    old_records="$(install:db_find_records db filter_old)"

    # if old record with same source and target exists, update the old target
    if [[ -n "$old_records" ]]; then
        local remove_old_target=false
        mapfile -t record_cmds <<<"$old_records"
        for record_cmd in "${record_cmds[@]}"; do
            eval "$record_cmd"

            local old_id="${record[id]}"
            local old_tgt="${record[target]}"
            local old_hash="${record[hash]}"
            local old_uid="${record[uid]}"

            if [[ ("$old_hash" == "symlink" && -L "$old_tgt" && \
                $old_tgt -ef $src) || (\
                "$old_hash" != "file" && -f "$old_tgt" && \
                "$(install:hash_file "$old_tgt")" == "$old_hash") ]]; then

                # if old target is still managed by bdm, update directly.
                log:info "removing old target $old_tgt"

                # set parameters for removing the old target
                local remove_old_target=true
                if [[ "$old_uid" == "$(id -u root)" ]]; then
                    local remove_asroot=true
                else
                    local remove_asroot=false
                fi
                if [[ "$old_hash" == "symlink" ]]; then
                    local remove_cmd=unlink
                else
                    local remove_cmd=rm
                fi
            elif [[ -L $old_tgt || -e $old_tgt ]]; then
                log:warning "$old_tgt no longer managed by bdm, " \
                    "Please remove it manually."
                return 1
            else
                log:warning "$old_tgt missing, reinstalling ..."
            fi

            # Remove updated old record from old db.
            # Anything remains in old db will be removed in `transaction_commit`
            db:remove_record db "$old_id"
        done

        # remove the old target at last to avoid removing multiple times
        if $remove_old_target; then
            # uninstall target
            if $remove_asroot; then
                sudo $remove_cmd "$old_tgt"
            else
                $remove_cmd "$old_tgt"
            fi
        fi
    else
        # if an old record is not fond, install this as a new record
        if [[ ("$install_type" == "symlink" && -L $tgt && $src -ef $tgt) || (\
            "$install_type" == "file" && -e $tgt && \
            "$(install:hash_file "$tgt")" == "$(install:hash_file "$src")") ]]; then

            # if source already installed correctly, simply update db
            log:warning "$src --> $tgt already installed, adding record ..."
            __add_new_record
            return 0
        elif [[ -L $tgt || -e $tgt ]]; then
            log:error "$tgt is not managed by bdm"
            return 1
        fi
    fi

    # Install target and add record to db.
    # For symlink, we do not care about file hash.
    if [[ "$install_type" == "symlink" ]]; then
        if [[ "$uid" == "$(id -u root)" ]]; then
            sudo ln -s "$src" "$tgt"
        elif [[ "$uid" == "$(id -u)" ]]; then
            ln -s "$src" "$tgt"
        else
            # install as other use, also require root permission
            sudo ln -s "$src" "$tgt"
            sudo chown -h "$uid:$gid" "$tgt"
        fi
    elif [[ "$install_type" == "file" ]]; then
        if [[ "$uid" == "$(id -u)" ]]; then
            install -m "$perm" -o "$uid" -g "$gid" "$src" "$tgt"
        else
            sudo install -m "$perm" -o "$uid" -g "$gid" "$src" "$tgt"
        fi
    fi
    __add_new_record
    log:info "$src --> $tgt installed"
}

# $1: target location
# $2: uid
# $3: gid
# $4: permission
install:directory() {
    local tgt old_records
    tgt="$(realpath -ms "$1")"
    uid="$(id -u "$2")"
    gid="$(id -g "$3")"
    perm="$4"

    filter() {
        local -n rec="$1"
        [[ ${rec[target]} == "$tgt" && ${rec[hash]} == "directory" ]]
    }
    new_records="$(install:db_find_records tmp_db filter)"
    old_records="$(install:db_find_records db filter)"
    if [[ -n "$new_records" ]]; then
        log:error "'$tgt' can only be installed once in a transaction."
        return 1
    fi

    if [[ -n "$old_records" ]]; then
        mapfile -t record_cmds <<<"$old_records"

        local remove_old_target=false
        for record_cmd in "${record_cmds[@]}"; do
            eval "$record_cmd"
            local old_id="${record[id]}"
            local old_tgt="${record[target]}"
            local old_uid="${record[uid]}"

            if [[ -d $old_tgt ]]; then
                log:info "removing old target $old_tgt"
                remove_old_target=true
                if [[ "$uid" == "$(id -u)" ]]; then
                    local remove_asroot=false
                else
                    local remove_asroot=true
                fi
            else
                log:info "$old_tgt missing, reinstalling ..."
            fi
            # remove from old database
            db:remove_record db "$old_id"
        done

        if $remove_old_target; then
            # remove old target
            if $remove_asroot; then
                sudo rmdir --ignore-fail-on-non-empty -p "$old_tgt"
            else
                rmdir --ignore-fail-on-non-empty -p "$old_tgt"
            fi
        fi
    fi

    if [[ "$uid" == "$(id -u)" ]]; then
        install -m "$perm" -o "$uid" -g "$gid" -d "$tgt"
    else
        sudo install -m "$perm" -o "$uid" -g "$gid" -d "$tgt"
    fi
    local -A record=(
        [id]="" [source]="" [target]="$tgt" [hash]="directory"
        [uid]="$uid" [gid]="$gid" [permission]="$perm"
    )
    install:db_add_record tmp_db record
    log:info "${tgt/%\//}/ created"
}

# $1: installation type (symlink, file)
# $2: source file/directory (relative paths will be translated to realpath)
# $3: target location
# $4: optional, set to "asroot" if install symlink as root
# $5: optional, set to "skiprec" to skip removing db record
# return: 0|1: caller should return this value, 2: caller should continue
install:remove_link_or_file() {
    local src tgt old_records new_records
    install_type="$1"
    src="$(realpath "$2")"
    tgt="$(realpath -ms "$3")"
    if ! [[ -e $src ]]; then
        log:error "$src does not exist"
        return 1
    fi

    if [[ "$install_type" == "symlink" ]]; then
        remove_cmd="unlink"
    elif [[ "$install_type" == "file" ]]; then
        remove_cmd="rm"
    fi

    local require_root="false"
    if [[ $4 == "asroot" ]]; then
        require_root="true"
    fi

    __remove_target() {
        # Remove target symlink
        if $require_root; then
            sudo $remove_cmd "$tgt"
        else
            $remove_cmd "$tgt"
        fi
        log:info "$src --> $tgt removed"
    }

    filter() {
        local -n rec="$1"
        [[ ${rec[source]} == "$src" && ${rec[target]} == "$tgt" ]]
    }
    old_records="$(install:db_find_records db filter)"
    new_records="$(install:db_find_records tmp_db filter)"
    if [[ -n "$old_records" || -n "$new_records" ]]; then
        local -a old_record_cmds=() new_record_cmds=()
        local -a old_records_to_remove=() new_records_to_remove=()
        local remove_cur_target=false

        mapfile -t old_record_cmds <<<"$old_records"
        mapfile -t new_record_cmds <<<"$new_records"

        local record_type="old"
        for record_cmd in "${old_record_cmds[@]}" "--" "${new_record_cmds[@]}"; do
            if [[ -z $record_cmd ]]; then continue; fi
            if [[ "$record_cmd" == "--" ]]; then
                record_type="new"
                continue
            fi

            local -A record=()
            eval "$record_cmd"
            local old_tgt="${record["target"]}"
            local old_hash="${record["hash"]}"
            if [[ ("$install_type" == "symlink" && -L $old_tgt && $old_tgt -ef $src) || (\
                "$install_type" == "file" && -f $old_tgt && \
                "$(install:hash_file "$old_tgt")" == "$old_hash") ]]; then
                remove_cur_target=true
            elif [[ -L $old_tgt || -e $old_tgt ]]; then
                log:warning "$old_tgt no longer managed by bdm, only removing record ..."
            else
                log:warning "$src --> $old_tgt not installed, only removing record ..."
            fi

            if [[ "$record_type" == old ]]; then
                old_records_to_remove+=("${record[id]}")
            elif [[ "$record_type" == new ]]; then
                new_records_to_remove+=("${record[id]}")
            fi
        done

        # same target are only removed once
        if $remove_cur_target; then
            log:info "removing $src --> $old_tgt ..."
            __remove_target
        fi

        if [[ $5 != "skiprec" ]]; then
            for id in "${old_records_to_remove[@]}"; do
                db:remove_record db "$id"
            done
            for id in "${new_records_to_remove[@]}"; do
                db:remove_record tmp_db "$id"
            done
        fi
    else
        if [[ ("$install_type" == "symlink" && -L $tgt && $src -ef $tgt) || (-f \
            $tgt && $(install:hash_file "$src") == $(install:hash_file "$tgt")) ]]; then
            log:warning "$src --> $tgt is installed but not recorded, uninstalling anyway..."
            __remove_target
        elif [[ -L $tgt || -e $tgt ]]; then
            log:warning "$tgt is not managed by bdm, skipping ..."
        else
            log:warning "$src --> $tgt does not exist, skipping ..."
        fi
    fi
}

# $1: target location
# $2: optional, set to "asroot" if root premission required
install:remove_directory() {
    local tgt old_records new_records
    tgt="$(realpath -ms "$1")"
    filter() {
        local -n rec="$1"
        [[ ${rec[target]} == "$tgt" && ${rec[hash]} == "directory" ]]
    }
    old_records="$(install:db_find_records db filter)"
    new_records="$(install:db_find_records tmp_db filter)"

    local do_rmdir=true
    if [[ -n "$old_records" || -n "$new_records" ]]; then
        local -a old_record_cmds=() new_record_cmds=()
        local -a old_records_to_remove=() new_records_to_remove=()

        mapfile -t old_record_cmds <<<"$old_records"
        mapfile -t new_record_cmds <<<"$new_records"

        local record_type="old"
        for record_cmd in "${old_record_cmds[@]}" "--" "${new_record_cmds[@]}"; do
            if [[ -z $record_cmd ]]; then continue; fi
            if [[ "$record_cmd" == "--" ]]; then
                record_type="new"
                continue
            fi

            eval "$record_cmd"
            local old_tgt="${record["target"]}"

            if [[ ! -d $old_tgt ]]; then
                log:warning "$old_tgt missing, removing record ..."
                do_rmdir=false
            fi

            if [[ "$record_type" == old ]]; then
                old_records_to_remove+=("${record[id]}")
            elif [[ "$record_type" == new ]]; then
                new_records_to_remove+=("${record[id]}")
            fi
        done

        for id in "${old_records_to_remove[@]}"; do
            db:remove_record db "$id"
        done
        for id in "${new_records_to_remove[@]}"; do
            db:remove_record tmp_db "$id"
        done
    else
        if [[ -d "$tgt" ]]; then
            log:warning "$tgt is installed but not recorded, uninstalling anyway..."
        else
            log:warning "$tgt does not exist"
            do_rmdir=false
        fi
    fi

    if $do_rmdir; then
        if [[ "$2" == "asroot" ]]; then
            sudo rmdir --ignore-fail-on-non-empty -p "$tgt"
        else
            rmdir --ignore-fail-on-non-empty -p "$tgt"
        fi
    fi
    log:info "${1/%\//}/ removed"
}

# clean entries in current db that does not have corresponding `source` file,
# and also remove associated targets if the target is managed by bdm
# $1: name of the db file
install:clean() {
    log:info "Cleaning current database ..."
    db:load "$STORAGE_DIR/$(basename "$1")" db_to_cleanup

    local record_cmds
    mapfile -t record_cmds <<<"$(db:all_values db_to_cleanup)"

    # decide the records to remove
    for record_cmd in "${record_cmds[@]}"; do
        eval "$record_cmd"
        local id="${record[id]}"
        local source=${record[source]}
        local target=${record[target]}
        local hash=${record[hash]}
        local uid=${record[uid]}

        # skip processing directories
        if [[ $hash == "directory" ]]; then
            continue
        fi

        # if source no longer exists, clean the target
        if [[ ! -e "$source" ]]; then
            log:info "$source --> $target invalid, removing ..."

            if [[ $uid == "$(id -u)" ]]; then
                identity="user"
            else
                identity="root"
            fi

            if [[ "$hash" == "symlink" ]]; then
                if [[ -L "$target" && $(realpath -ms "$target") == "$target" ]]; then
                    log:info "Removing $target"
                    if [[ "$identity" == "user" ]]; then
                        unlink "$target"
                    else
                        sudo unlink "$target"
                    fi
                fi
            else
                if [[ -f "$target" && $(install:hash_file "$target") == "$hash" ]]; then
                    log:info "Removing $target"
                    if [[ "$identity" == "user" ]]; then
                        rm "$target"
                    else
                        sudo rm "$target"
                    fi
                fi
            fi
            db:remove_record db_to_cleanup "$id"
        fi
    done
    db:save "$STORAGE_DIR/$(basename "$1")" db_to_cleanup
}

# remove all records in current db, remove associated targets
install:purge() {
    local record_cmds
    mapfile -t record_cmds <<<"$(db:all_values db)"
    if [[ -z ${record_cmds[*]} ]]; then return 0; fi

    for record_cmd in "${record_cmds[@]}"; do
        eval "$record_cmd"
        local source="${record[source]}"
        local target="${record[target]}"
        local hash="${record[hash]}"
        local uid="${record[uid]}"

        # TODO: purge directory at last,
        if [[ $hash == "directory" ]]; then
            if [[ "$uid" == "$(id -u)" ]]; then
                rmdir --ignore-fail-on-non-empty -p "$target"
            else
                sudo rmdir --ignore-fail-on-non-empty -p "$target"
            fi
            log:info "${target/%\//}/ removed"
        else
            if [[ "$uid" == "$(id -u)" ]]; then
                identity="asuser"
            else
                identity="asroot"
            fi

            if [[ "$hash" == "symlink" ]]; then
                local install_type="symlink"
            else
                local install_type="file"
            fi
            install:remove_link_or_file "$install_type" "$source" "$target" "$identity" "skiprec"
        fi
    done
    db:purge db
}

# Backup file/link/directory if it's not installed by bdm.
# If $1 (source file) is not provided, will only check databases, otherwise will
# also check if the target file matches the source file if database check fails.
# $1: source file (optional)
# $2: target location
install:backup_if_not_installed() {
    if [[ $# -eq 1 ]]; then
        tgt="$(realpath -ms "$1")"
    else
        src="$(realpath "$1")"
        tgt="$(realpath -ms "$2")"
    fi

    # if target does not exist, nothing needs to be done
    if [[ ! -e "$tgt" && ! -L "$tgt" ]]; then
        return 0
    fi

    # utility function for backing up the target
    backup_target(){
        target="$1"
        target_uid="$(stat -c %u "$target")"
        if [[ "$target_uid" == "$(id -u root)" ]]; then
            sudo mv "$target" "${target}.bdm_bak_$(date +%s)"
        else
            mv "$target" "${target}.bdm_bak_$(date +%s)"
        fi
    }

    # check if the target is recorded as installed in database
    filter() {
        local -n rec="$1"
        [[ ${rec[target]} == "$tgt" ]]
    }
    old_records="$(install:db_find_records db filter)"
    new_records="$(install:db_find_records tmp_db filter)"
    if [[ -n "${old_records}" ]]; then
        # As each target can only be installed once, we can safely assume
        # that there is only one record if target is found in old db
        mapfile -t record_cmds <<<"$old_records"
        eval "${record_cmds[0]}"

        local old_id="${record[id]}"
        local old_src="${record[source]}"
        local old_hash="${record[hash]}"
        local old_uid="${record[uid]}"

        if [[ ("$old_hash" == "symlink" && "$tgt" -ef "$old_src") || (\
            "$old_hash" == "directory" && -d "$tgt") || (\
            "$old_hash" != "symlink" && "$old_hash" != "directory" && -f \
            "$tgt" && "$(install:hash_file "$tgt")" == "$old_hash") ]]; then
            # if correctly installed, do nothing.
            return 0
        else
            # if modified externally, backup and remove record from old_db
            backup_target "$tgt"
            db:remove_record db "$old_id"
            return 0
        fi
    elif [[ -n "${new_records}" ]]; then
        # If the tgt is just installed within the same transaction, do nothing
        return 0
    fi

    # if not present in database, but src provided, check against src
    if [[ -n "$src" ]]; then
        if [[ (-L "$tgt" && "$tgt" -ef "$src") || (-f "$tgt" && \
            $(install:hash_file "$tgt") == "$(install:hash_file "$src")") ]]; then
            return 0
        fi
    fi

    # if all check failed, just back it up
    backup_target "$tgt"
}

## Install-DB I/O functions ####################################################

# Records are store in a plain text file, with each record entry per row
# the first line of that file is the maximum record id

readonly -A __entries=(
    ["id"]=1         # a unique id to identify this record
    ["source"]=1     # absolute resolved source path
    ["target"]=1     # absolut resolved destination path
    ["hash"]=1       # file hash
    ["uid"]=1        # user id of the target file
    ["gid"]=1        # group id of the target file
    ["permission"]=1 # file permissions (e.g. 755)
)

# $1: db name
# $2: a function that accepts name of the associated array
# print: list of records, separated by '\n'
install:db_find_records() {
    while read -r record_cmd; do
        if [[ -z $record_cmd ]]; then continue; fi
        unset record
        eval "$record_cmd"
        if "$2" record; then
            echo "$record_cmd"
        fi
    done <<<"$(db:all_values "$1")"
}

# add one record to db
# $1: db name
# $2: associated array name
# if the `id` entry is empty, will generated a unique id instead.
install:db_add_record() {
    local record_cmd
    record_cmd="$(declare -p "$2")"
    eval "${record_cmd/ $2=/ record=}"

    for key in "${!record[@]}"; do
        if [[ -z "${__entries["$key"]}" ]]; then
            error "$key must exist in record"
            return 1
        fi
    done

    if [[ -z "${record[id]}" ]]; then
        local max_id
        max_id=$(db:all_keys "$1" | sort -n | tail -n 1)
        max_id=${max_id:0}
        record[id]="$((max_id + 1))"
    fi

    db:add_record "$1" "${record[id]}" "$(typeset -p record)"
}

# $1: path to the file
# print: file hash
install:hash_file() {
    local md5
    read -r md5 _ <<<"$(md5sum "$1")"
    echo "${md5[0]}"
}

## Database I/O functions ######################################################

# $1: db file (use /dev/null for empty db)
# $2: db name
db:load() {
    local file="$1"
    declare -gA "$2=()"
    cmd=$(cat "$file")
    cmd="${cmd/ db=/ $2=}"
    cmd="${cmd/#declare /declare -g }"
    eval "$cmd"
}

# $1: db file
# $2: db name
db:save() {
    mkdir -p "$(dirname "$1")"
    local cmd
    cmd="$(declare -p "$2")"
    echo "${cmd/ $2=/ db=}" >|"$1"
}

# $1: db name
db:all_keys() {
    local -n __db="$1"
    if [[ ${#__db[@]} -eq 0 ]]; then return; fi
    for key in "${!__db[@]}"; do
        echo "$key"
    done
}

# $1: db name
db:all_values() {
    local -n __db="$1"
    if [[ ${#__db[@]} -eq 0 ]]; then return; fi
    for value in "${__db[@]}"; do
        echo "$value"
    done
}

# get record by key
# $1: db name
# $2: key
db:get_record() {
    local -n __db="$1"
    echo "${__db["$2"]}"
}

# add one record to currently loaded db
# $1: db name
# $2: key
# $3: value
db:add_record() {
    eval "$1[\"$2\"]=\"$3\""
}

# $1: db
# $2: key
db:remove_record() {
    eval "unset $1[\"$2\"]"
}

#1: db
db:purge() {
    declare -gA "$1=()"
}
