#!/bin/bash

#shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")"/utils.sh

## Transaction functions #######################################################

# Before executing the `install*` commands, `transaction_start` should be called
# to properly clean the residue of last installlation
#
# When executing the `install*` commands, informations will be temporarily
# stored into ".DINFO.TMP" file.
#
# When all installaAtion is done, `transaction_commit` should be executed to
# remove the entries left in "$1/.DINFO" file and move ".DINFO.TMP" to
# ".DINFO" (see bootstrap_imports.sh)

# $1: dotfile directory
transaction_start() {
    if [[ -f "$1/.DINFO.TMP" ]]; then
        warning "Last installation seems to be interrupted, cleaning ..."
        rm "$1/.DINFO.TMP"
    fi
}

# $1: dotfile directory
transaction_commit() {
    if [[ ! -f "$1/.DINFO.TMP" ]]; then
        return 0
    fi

    if [[ -f "$1/.DINFO" ]]; then
        purge "$1"
    fi

    mv "$1/.DINFO.TMP" "$1/.DINFO"
}

## Install/Uninstall functions #################################################

# $1: dotfile directory
# $2: installation type (symlink, file)
# $3: source file
# $4: target location
# $5: uid
# $6: gid
# $7: permission
# return: 0|1: caller should return this value, 2: caller should continue
install_link_or_file() {
    local db_dir src tgt uid gid perm old_records
    db_dir="$1"
    install_type="$2"
    src="$(realpath "$3")"
    tgt="$(realpath -ms "$4")"
    uid="$(id -u "$5")"
    gid="$(id -g "$6")"
    perm="$7"

    if ! [[ -e $src ]]; then
        error "$src does not exist"
        return 1
    fi

    if [[ $install_type == "symlink" ]]; then
        __add_new_record() {
            __add_record "$db_dir/.DINFO.TMP" 0 "$src" "$tgt" "symlink" "$uid" "$gid" "symlink"
        }
    elif [[ $install_type == "file" ]]; then
        __add_new_record() {
            __add_record "$db_dir/.DINFO.TMP" 0 "$src" "$tgt" "$(__hash_file "$tgt")" "$uid" "$gid" "$perm"
        }
    fi

    # skip if already installed as new target
    new_records="$(__find_records "$1/.DINFO.TMP" "source" "$src" "target" "$tgt")"
    if [[ -n "$new_records" ]]; then
        error "$src --> $tgt can only be installed once in a transaction."
        return 1
    fi

    # if old record with same source and target exists, update the old target
    old_records="$(__find_records "$1/.DINFO" "source" "$src" "target" "$tgt")"
    if [[ -n "$old_records" ]]; then
        mapfile -t records <<<"$old_records"
        local i=0
        local remove_old_target=false
        while [[ $((i * ${#__entries[@]})) -lt ${#records[@]} ]]; do
            local start="$((i * ${#__entries[@]}))"
            local end="$(((i + 1) * ${#__entries[@]}))"
            record=("${records[@]:$start:$end}")
            local old_id="${record[${__entry_offset["id"]}]}"
            local old_tgt="${record[${__entry_offset["target"]}]}"
            local old_hash="${record[${__entry_offset["hash"]}]}"
            local old_uid="${record[${__entry_offset["uid"]}]}"

            if [[ ("$old_hash" == "symlink" && -L "$old_tgt" && \
                $old_tgt -ef $src) || (\
                "$old_hash" != "symlink" && -f "$old_tgt" && \
                "$(__hash_file "$old_tgt")" == "$old_hash") ]]; then

                # if old target is still managed by bdm, update directly.
                info "removing old target $old_tgt"

                # set parameters for removing the old target
                local remove_old_target=true
                if [[ "$old_uid" == "$(id -u)" ]]; then
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
                warning "$old_tgt no longer managed by bdm, " \
                    "Please remove it manually before proceeding."
                return 1
            else
                warning "$old_tgt missing, reinstalling ..."
            fi

            ((++i))
            # Remove updated old record from old db.
            # Anything remains in old db will be removed in `transaction_commit`
            __remove_record "$1/.DINFO" "$old_id"
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
            "$(__hash_file "$tgt")" == "$(__hash_file "$src")") ]]; then

            # if source already installed correctly, simply update db
            warning "$src --> $tgt already installed, adding record ..."
            __add_new_record
            return 0
        elif [[ -L $tgt || -e $tgt ]]; then
            error "$tgt is not managed by bdm"
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
    info "$src --> $tgt installed"
}

# $1: dotfile directory
# $2: target location
# $3: uid
# $4: gid
# $5: permission
install_directory() {
    local tgt old_records
    tgt="$(realpath -ms "$2")"
    uid="$(id -u "$3")"
    gid="$(id -g "$4")"
    perm="$5"

    old_records="$(__find_records "$1/.DINFO" "target" "$tgt" "hash" "directory")"
    if [[ -n "$old_records" ]]; then
        mapfile -t records <<<"$old_records"

        local i=0
        local remove_old_target=false
        while [[ $((i * ${#__entries[@]})) -lt ${#records[@]} ]]; do
            local start="$((i * ${#__entries[@]}))"
            local end="$(((i + 1) * ${#__entries[@]}))"
            local record=("${records[@]:$start:$end}")
            local old_id="${record[${__entry_offset["id"]}]}"
            local old_tgt="${record[${__entry_offset["target"]}]}"
            local old_uid="${record[${__entry_offset["uid"]}]}"

            if [[ -d $old_tgt ]]; then
                info "removing old target $old_tgt"
                remove_old_target=true
                if [[ "$uid" == "$(id -u)" ]]; then
                    local remove_asroot=false
                else
                    local remove_asroot=true
                fi
            else
                info "$old_tgt missing, reinstalling ..."
            fi
            # remove from old database
            __remove_record "$1/.DINFO" "$old_id"
            ((++i))
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
    __add_record "$1/.DINFO.TMP" 0 "directory" "$tgt" "directory" "$uid" "$gid" "$perm"
    info "${tgt/%\//}/ created"
}

# $1: dotfile directory
# $2: installation type (symlink, file)
# $3: source file/directory (relative paths will be translated to realpath)
# $4: target location
# $5: optional, set to "asroot" if install symlink as root
# $6: optional, set to "skiprec" to skip removing db record
# return: 0|1: caller should return this value, 2: caller should continue
remove_link_or_file() {
    local src tgt raw_records
    install_type="$2"
    src="$(realpath "$3")"
    tgt="$(realpath -ms "$4")"
    if ! [[ -e $src ]]; then
        error "$src does not exist"
        return 1
    fi

    if [[ "$install_type" == "symlink" ]]; then
        remove_cmd="unlink"
    elif [[ "$install_type" == "file" ]]; then
        remove_cmd="rm"
    fi

    local require_root="false"
    if [[ $5 == "asroot" ]]; then
        require_root="true"
    fi

    __remove_target() {
        # Remove target symlink
        if $require_root; then
            sudo $remove_cmd "$tgt"
        else
            $remove_cmd "$tgt"
        fi
        info "$src --> $tgt removed"
    }

    raw_records="$(__find_records "$1/.DINFO" "source" "$src" "target" "$tgt")"
    if [[ -n "$raw_records" ]]; then
        local records
        mapfile -t records <<<"$raw_records"
        i=0
        while [[ $((i * ${#__entries[@]})) -lt ${#records[@]} ]]; do
            local start="$((i * ${#__entries[@]}))"
            local end="$(((i + 1) * ${#__entries[@]}))"
            local record=("${records[@]:$start:$end}")
            local old_id="${record[${__entry_offset["id"]}]}"
            local old_tgt="${record[${__entry_offset["target"]}]}"
            local old_hash="${record[${__entry_offset["hash"]}]}"
            local old_uid="${record[${__entry_offset["uid"]}]}"

            if [[ ("$install_type" == "symlink" && -L $old_tgt && $old_tgt -ef $src) || (\
                "$install_type" == "file" && -f $old_tgt && \
                "$(__hash_file "$old_tgt")" == "$old_hash") ]]; then
                # if old target is correctly installed, simply remove it
                info "removing $src --> $old_tgt ..."
                __remove_target
            elif [[ -L $old_tgt || -e $old_tgt ]]; then
                warning "$old_tgt no longer managed by bdm, only removing record ..."
            else
                warning "$src --> $old_tgt not installed, only removing record ..."
            fi

            if [[ $6 != "skiprec" ]]; then
                __remove_record "$1/.DINFO" "$old_id"
            fi
            ((++i))
        done
    else
        if [[ ("$install_type" == "symlink" && -L $tgt && $src -ef $tgt) || (-f \
            $tgt && $(__hash_file "$src") == $(__hash_file "$tgt")) ]]; then
            warning "$src --> $tgt is installed but not recorded, uninstalling anyway..."
            __remove_target
        elif [[ -L $tgt || -e $tgt ]]; then
            warning "$tgt is not managed by bdm, skipping ..."
        else
            warning "$src --> $tgt does not exist, skipping ..."
        fi
    fi
}

# $1: dotfile directory
# $2: target location
# $3: optional, set to "asroot" if root premission required
remove_directory() {
    local tgt raw_records
    tgt="$(realpath -ms "$2")"
    raw_records="$(__find_records "$1/.DINFO" "target" "$tgt" "hash" "directory")"

    local do_rmdir=true
    if [[ -n "$raw_records" ]]; then
        local records
        mapfile -t records <<<"$raw_records"

        i=0
        while [[ $((i * ${#__entries[@]})) -lt ${#records[@]} ]]; do
            local start="$((i * ${#__entries[@]}))"
            local end="$(((i + 1) * ${#__entries[@]}))"
            local record=("${records[@]:$start:$end}")
            local old_id="${record[${__entry_offset["id"]}]}"
            local old_tgt="${record[${__entry_offset["target"]}]}"

            if [[ -d $old_tgt ]]; then
                __remove_record "$1/.DINFO" "$old_id"
            else
                warning "$old_tgt missing, removing record ..."
                __remove_record "$1/.DINFO" "$old_id"
                do_rmdir=false
            fi
            ((++i))
        done
    else
        if [[ -d "$tgt" ]]; then
            warning "$tgt is installed but not recorded, uninstalling anyway..."
        else
            warning "$tgt does not exist"
            do_rmdir=false
        fi
    fi

    if $do_rmdir; then
        if [[ "$4" == "asroot" ]]; then
            sudo rmdir --ignore-fail-on-non-empty -p "$tgt"
        else
            rmdir --ignore-fail-on-non-empty -p "$tgt"
        fi
    fi
    info "${2/%\//}/ removed"
}

# clean entries in .DINFO file that does not have corresponding `source` file,
# and also remove associated targets if the target is managed by bdm
# $1: dotfile directory
clean() {
    info "cleaning $1/.DINFO ..."
    if [[ -f "$1/.DINFO" ]]; then
        local lines
        mapfile -t lines <"$1/.DINFO"
        lines=("${lines[@]:1}")

        # decide the records to remove
        local -A records_to_remove
        local record_idx=0
        while [[ $((record_idx * ${#__entries[@]})) -lt "${#lines[@]}" ]]; do
            local line_base=$((record_idx * ${#__entries[@]}))
            local source=${lines[$((line_base + __entry_offset["source"]))]}
            local target=${lines[$((line_base + __entry_offset["target"]))]}
            local hash=${lines[$((line_base + __entry_offset["hash"]))]}
            local uid=${lines[$((line_base + __entry_offset["uid"]))]}

            # skip processing directories
            if [[ $hash == "directory" ]]; then
                continue
            fi

            # if source no longer exists, clean the target
            if [[ ! -e "$source" ]]; then
                records_to_remove[$record_idx]=1
                info "$source --> $target invalid, removing ..."

                if [[ $uid == "$(id -u)" ]]; then
                    identity="asuser"
                else
                    identity="asroot"
                fi

                if [[ "$hash" == "symlink" ]]; then
                    install_type="symlink"
                else
                    install_type="file"
                fi

                remove_link_or_file "$1" "$install_type" "$source" "$target" "$identity" "skiprec"
            fi
            ((++record_idx))
        done
    fi

    # write back to file
    : >|"$1/.DINFO"
    record_idx=0
    while [[ $((record_idx * ${#__entries[@]})) -lt "${#lines[@]}" ]]; do
        local line=$((record_idx * ${#__entries[@]}))
        if [[ -z ${records_to_remove["$record_idx"]} ]]; then
            for offset in $(seq 0 "$(("${#__entries[@]}" - 1))"); do
                echo "${lines["$((line + offset))"]}" >>"$1/.DINFO"
            done
        fi
        ((++record_idx))
    done
}

# remove all entires in .DINFO ifle, remove associated targets
# $1: dotfile directory
purge() {
    info "purging $1/.DINFO ..."
    if [[ -f "$1/.DINFO" ]]; then
        local lines
        mapfile -t lines <"$1/.DINFO"
        lines=("${lines[@]:1}")
        record_idx=0
        while [[ $((record_idx * ${#__entries[@]})) -lt "${#lines[@]}" ]]; do
            local line_base=$((record_idx * ${#__entries[@]}))
            local source=${lines[$((line_base + __entry_offset["source"]))]}
            local target=${lines[$((line_base + __entry_offset["target"]))]}
            local hash=${lines[$((line_base + __entry_offset["hash"]))]}
            local uid=${lines[$((line_base + __entry_offset["uid"]))]}

            if [[ $hash == "directory" ]]; then
                if [[ "$uid" == "$(id -u)" ]]; then
                    rmdir --ignore-fail-on-non-empty -p "$target"
                else
                    sudo rmdir --ignore-fail-on-non-empty -p "$target"
                fi
                info "${target/%\//}/ removed"
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
                remove_link_or_file "$1" "$install_type" "$source" "$target" "$identity" "skiprec"
            fi
            ((++record_idx))
        done
    fi
    if [[ -f $1/.DINFO ]]; then rm "$1/.DINFO"; fi
}

## Database I/O functions ######################################################

# Records are store in a plain text file, with each record entry per row
# the first line of that file is the maximum record id

declare -a __entries=(
    "id"         # a unique id to identify this record
    "source"     # absolute resolved source path
    "target"     # absolut resolved destination path
    "hash"       # file hash
    "uid"        # user id of the target file
    "gid"        # group id of the target file
    "permission" # file permissions (e.g. 755)
)
declare -A __entry_offset

declare i=0
for r in "${__entries[@]}"; do
    __entry_offset["$r"]=$i
    ((++i))
done
unset i

# $1: db file
# ${@:1}: [entry 1 name, entry 1 value], ... return an entry if all criteria passes
# print: [entry 1, entry 2, ...], ... (list of records, separated by \n)
__find_records() {
    if [[ -f "$1" ]]; then
        local lines
        mapfile -t lines <"$1"
        lines=("${lines[@]:1}")
        shift

        local -a entry_offsets=()
        local -a entry_values=()

        while [[ $# -gt 0 ]]; do
            if [[ -n "${__entry_offset["$1"]}" ]]; then
                entry_offsets+=("${__entry_offset["$1"]}")
                shift
                entry_values+=("$1")
                shift
            else
                error "Unknown record name $1"
                return 1
            fi
        done

        local i=0
        while [[ $((i * ${#__entries[@]})) -lt "${#lines[@]}" ]]; do
            local match=true
            for j in $(seq 0 "$((${#entry_offsets[@]} - 1))"); do
                if [[ "${lines[$((i * ${#__entries[@]} + ${entry_offsets[$j]}))]}" != \
                    "${entry_values[$j]}" ]]; then
                    match=false
                    break
                fi
            done

            if $match; then
                for j in $(seq 0 "$(("${#__entries[@]}" - 1))"); do
                    echo "${lines[$((i * ${#__entries[@]} + j))]}"
                done
            fi
            ((++i))
        done
    fi
}

# ad one record to db
# $1: db file
# ${@:2}: record content, one entry per line.
# the `id` entry will be ignored and use a generated unique id instead.
__add_record() {
    local db="$1"
    shift

    # read old db into array
    local -a db_lines
    if [[ -f "$db" ]]; then
        mapfile -t db_lines <"$db"
        db_lines=("${db_lines[@]:1}")
    fi

    if [[ $# -ne ${#__entries[@]} ]]; then
        error "record content must have ${#__entries[@]} entries"
        return 1
    fi

    local max_id
    if [[ -f "$db" ]]; then max_id="$(head -n 1 "$db")"; else max_id=0; fi

    local i=0
    for entry in "$@"; do
        if [[ "${__entries[$i]}" == "id" ]]; then
            ((++max_id))
            db_lines+=("$max_id")
        else
            db_lines+=("$entry")
        fi
        ((++i))
    done

    # overwrite original database
    echo "$max_id" >|"$db"
    for line in "${db_lines[@]}"; do
        echo "$line" >>"$db"
    done
}

# $1: db file
# $2: record id
__remove_record() {
    if [[ -f "$1" ]]; then
        # read in db and remove record
        local lines
        mapfile -t lines <"$1"
        max_id="${lines[0]}"
        lines=("${lines[@]:1}")

        local i=0
        while [[ $((i * ${#__entries[@]})) -lt ${#lines[@]} ]]; do
            local id=${lines[$((i * ${#__entries[@]} + __entry_offset["id"]))]}
            if [[ $id == "$2" ]]; then
                local start=$((i * ${#__entries[@]}))
                local end=$((i * ${#__entries[@]} + ${#__entries[@]}))
                lines=("${lines[@]:0:$start}" "${lines[@]:$end}")
                break
            fi
            ((++i))
        done

        # re-write to db file
        echo "$max_id" >|"$1"
        for line in "${lines[@]}"; do
            echo "$line" >>"$1"
        done
    fi
}

# $1: path to the file
# print: file hash
__hash_file() {
    local md5
    read -r md5 _ <<<"$(md5sum "$1")"
    echo "${md5[0]}"
}
