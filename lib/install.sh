#!/bin/bash

#shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")"/utils.sh

declare -a __record=("source" "target" "hash" "asroot")
declare -A __record_offset

declare i=0
for r in "${__record[@]}"; do
    __record_offset["$r"]=$i
    ((++i))
done
unset i

# $1: directory of the .DINFO file
# $2: record name
# $3: record value to find
# print: index, [record] (separated by \n), None if not fonud
__find_record() {
    if [[ -f "$1/.DINFO" ]]; then
        local lines
        mapfile -t lines <"$1/.DINFO"
        if [[ -z "${__record_offset["$2"]}" ]]; then
            error "Unknown record name $2"
            return 1
        fi
        local record_off="${__record_offset["$2"]}"

        local i=0
        while [[ $((i * ${#__record[@]})) -lt "${#lines[@]}" ]]; do
            if [[ "${lines[$((i * ${#__record[@]} + record_off))]}" == "$3" ]]; then
                echo "$i"
                for j in $(seq 0 "$(("${#__record[@]}" - 1))"); do
                    echo "${lines[$((i * ${#__record[@]} + j))]}"
                done
                return
            fi
            ((++i))
        done
    fi
}

# $1: directory of the .DINFO file
# $2: record index
__remove_record() {
    if [[ -f "$1/.DINFO" ]]; then
        # read in db and remove record
        local lines
        mapfile -t lines <"$1/.DINFO"
        local start=$(($2 * ${#__record[@]}))
        local end=$(($2 * ${#__record[@]} + ${#__record[@]}))
        lines=("${lines[@]:0:$start}" "${lines[@]:$end}")

        # re-write to db file
        : >|"$1/.DINFO"
        for line in "${lines[@]}"; do
            echo "${line}" >>"$1/.DINFO"
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

# $1: directory of the .DINFO file
# ${@:2}: record content, one entry per line
__add_record() {
    local db="$1/.DINFO"
    shift
    if [[ $# -ne ${#__record[@]} ]]; then
        error "record content must have ${#__record[@]} entries"
        return 1
    fi
    for entry in "$@"; do
        echo "$entry" >>"$db"
    done
}

# $1: directory of the .DINFO file
# $2: installation type (symlink, file)
# $3: source file/directory (relative paths will be translated to realpath)
# $4: target location
# $5: optional, set to "asroot" if install symlink as root
# return: 0|1: caller should return this value, 2: caller should continue
__install_handle_old_record() {
    local src tgt raw_record
    install_type="$2"
    src="$(realpath "$3")"
    tgt="$(realpath -ms "$4")"

    if ! [[ -f $src ]]; then
        error "$src does not exist"
        return 1
    fi
    raw_record="$(__find_record "$1" "source" "$src")"

    if [[ -n "$raw_record" ]]; then
        local record
        mapfile -t record <<<"$raw_record"
        local record_idx="${record[0]}"
        record=("${record[@]:1}")
        local old_tgt="${record[${__record_offset["target"]}]}"
        local old_hash="${record[${__record_offset["hash"]}]}"
        local asroot="${record[${__record_offset["asroot"]}]}"

        local remove_cmd
        if [[ $install_type == "symlink" ]]; then
            remove_cmd="unlink"
        elif [[ $install_type == "file" ]]; then
            remove_cmd="rm"
        fi

        __remove_old_target() {
            # uninstall target
            if "$asroot"; then
                sudo $remove_cmd "$old_tgt"
            else
                $remove_cmd "$old_tgt"
            fi
        }

        if [[ ("$install_type" == "symlink" && -L "$old_tgt" && $old_tgt -ef $src) || (\
            "$install_type" == "file" && -f "$old_tgt" && \
            "$(__hash_file "$old_tgt")" == "$old_hash") ]]; then
            # if source already installed correctly, check if update old target
            if [[ "$old_tgt" != "$tgt" ]]; then
                info "$src --> $old_tgt changed to $tgt, reinstalling ..."
                __remove_old_target
            elif [[ "$install_type" == "file" && \
                "$(__hash_file "$old_tgt")" != "$(__hash_file "$src")" ]]; then
                info "$src --> $old_tgt content changed, reinstalling ..."
                __remove_old_target
            else
                info "$src --> $old_tgt unchanged"
                return 0
            fi
        elif [[ -L $old_tgt || -e $old_tgt ]]; then
            warning "$old_tgt no longer managed by bdm, removing record ..."
        else
            warning "$old_tgt missing, reinstalling ..."
        fi

        # remove old record from db
        __remove_record "$1" "$record_idx"
    else
        if [[ ("$install_type" == "symlink" && -L $tgt && $src -ef $tgt) || (\
            "$install_type" == "file" && -e $tgt && \
            "$(__hash_file "$tgt")" == "$(__hash_file "$src")") ]]; then

            # if source already installed correctly, simply update db
            warning "$src --> $tgt already installed, adding record ..."
            if [[ "$5" == "asroot" ]]; then
                asroot="true"
            else
                asroot="false"
            fi

            if [[ $install_type == "symlink" ]]; then
                new_hash="symlink"
            elif [[ $install_type == "file" ]]; then
                new_hash="$(__hash_file "$tgt")"
            elif [[ $install_type == "directory" ]]; then
                src="directory"
                new_hash="directory"
            fi

            __add_record "$1" "$src" "$tgt" "$new_hash" "$asroot"
            return 0
        elif [[ -L $tgt || -e $tgt ]]; then
            error "$tgt is not managed by bdm"
            return 1
        fi
    fi

    # caller should continue processing
    return 2
}

# $1: directory of the .DINFO file
# $2: source file/directory (relative paths will be translated to realpath)
# $3: target location
# $4: optional, set to "asroot" if install symlink as root
installSymLink() {
    local src tgt raw_record
    src="$(realpath "$2")"
    tgt="$(realpath -ms "$3")"

    __install_handle_old_record "$1" "symlink" "$2" "$3" "$4"
    if [[ $? != 2 ]]; then return $?; fi

    # Install target and add record to db.
    # For symlink, we do not care about file hash.
    if [[ "$4" == "asroot" ]]; then
        sudo mkdir -p "$(dirname "$tgt")"
        sudo ln -s "$src" "$tgt"
        __add_record "$1" "$src" "$tgt" "symlink" "true"
    else
        mkdir -p "$(dirname "$tgt")"
        ln -s "$src" "$tgt"
        __add_record "$1" "$src" "$tgt" "symlink" "false"
    fi
    info "$src --> $tgt link created"
}

# $1: directory of the .DINFO file
# $2: source file/directory
# $3: target location
# $4: optional, set to "asroot" if install file as root
installFile() {
    local src tgt raw_record
    src="$(realpath "$2")"
    tgt="$(realpath -ms "$3")"

    __install_handle_old_record "$1" "file" "$2" "$3" "$4"
    if [[ $? != 2 ]]; then return $?; fi

    # Install target and add record to db.
    # For symlink, we do not care about file hash.
    if [[ "$4" == "asroot" ]]; then
        sudo mkdir -p "$(dirname "$tgt")"
        sudo cp "$src" "$tgt"
        __add_record "$1" "$src" "$tgt" "$(__hash_file "$tgt")" "true"
    else
        mkdir -p "$(dirname "$tgt")"
        cp "$src" "$tgt"
        __add_record "$1" "$src" "$tgt" "$(__hash_file "$tgt")" "false"
    fi
    info "$src --> $tgt installed"
}

# $1: directory of the .DINFO file
# $2: target location
# $3: optional, set to "asroot" if root premission required
installDirectory() {
    local tgt raw_record
    tgt="$(realpath -ms "$2")"
    raw_record="$(__find_record "$1" "target" "$tgt")"
    if [[ -n "$raw_record" ]]; then
        local record
        mapfile -t record <<<"$raw_record"
        local record_idx="${record[0]}"
        record=("${record[@]:1}")
        local target="${record[${__record_offset["target"]}]}"
        local asroot="${record[${__record_offset["asroot"]}]}"

        if [[ -d $target ]]; then
            info "$target unchanged"
            return 0
        else
            info "$target missing, reinstalling ..."
        fi
    fi

    if [[ "$3" == "asroot" ]]; then
        sudo mkdir -p "$tgt"
        __add_record "$1" "directory" "$tgt" "directory" "true"
    else
        mkdir -p "$tgt"
        __add_record "$1" "directory" "$tgt" "directory" "false"
    fi
    info "${tgt/%\//}/ created"
}

# $1: directory of the .DINFO file
# $2: installation type (symlink, file)
# $3: source file/directory (relative paths will be translated to realpath)
# $4: target location
# $5: optional, set to "asroot" if install symlink as root
# $6: optional, set to "skiprec" to skip removing db record
# return: 0|1: caller should return this value, 2: caller should continue
__remove_handle_old_record() {
    local src tgt raw_record
    install_type="$2"
    src="$(realpath "$3")"
    tgt="$(realpath -ms "$4")"
    if ! [[ -f $src ]]; then
        error "$src does not exist"
        return 1
    fi

    if [[ "$install_type" == "symlink" ]]; then
        remove_cmd="unlink"
    elif [[ "$install_type" == "file" ]]; then
        remove_cmd="rm"
    fi

    if [[ $5 == "asroot" ]]; then
        local require_root="true"
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

    raw_record="$(__find_record "$1" "source" "$src")"
    if [[ -n "$raw_record" ]]; then
        local record
        mapfile -t record <<<"$raw_record"
        local record_idx="${record[0]}"
        record=("${record[@]:1}")
        local old_tgt="${record[${__record_offset["target"]}]}"
        local asroot="${record[${__record_offset["asroot"]}]}"

        if [[ "$old_tgt" != "$tgt" ]]; then
            warning "$old_tgt (recorded) != $tgt (required), ignoring the latter ..."
        fi

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
            __remove_record "$1" "$record_idx"
        fi
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

# $1: directory of the .DINFO file
# $2: source file/directory
# $3: target location
# $4: optional, set to "asroot" if root premission required
removeSymLink() {
    __remove_handle_old_record "$1" "symlink" "$2" "$3" "$4"
}

# $1: directory of the .DINFO file
# $2: source file/directory
# $3: target location
# $4: optional, set to "asroot" if root premission required
removeFile() {
    __remove_handle_old_record "$1" "file" "$2" "$3" "$4"
}

# $1: directory of the .DINFO file
# $2: target location
# $3: optional, set to "asroot" if root premission required
removeDirectory() {
    local tgt raw_record
    tgt="$(realpath -ms "$2")"
    raw_record="$(__find_record "$1" "target" "$tgt")"
    if [[ -n "$raw_record" ]]; then
        local record
        mapfile -t record <<<"$raw_record"
        local record_idx="${record[0]}"
        record=("${record[@]:1}")
        local target="${record[${__record_offset["target"]}]}"
        local asroot="${record[${__record_offset["asroot"]}]}"

        if [[ -d $target ]]; then
            __remove_record "$1" "$record_idx"
        else
            warning "$target missing, removing record ..."
            __remove_record "$1" "$record_idx"
            return 0
        fi
    else
        warning "$tgt is installed but not recorded, uninstalling anyway..."
    fi

    if [[ "$4" == "asroot" ]]; then
        sudo rmdir -p "$tgt"
    else
        rmdir -p "$tgt"
    fi
    info "${2/%\//}/ removed"
}

# clean entries in .DINFO file that does not have corresponding `source` file,
# and also remove associated targets if the target is managed by bdm
# $1: directory of the .DINFO file
clean() {
    info "cleaning $1/.DINFO ..."
    if [[ -f "$1/.DINFO" ]]; then
        local lines
        mapfile -t lines <"$1/.DINFO"

        # decide the records to remove
        local -A records_to_remove
        local record_idx=0
        while [[ $((record_idx * ${#__record[@]})) -lt "${#lines[@]}" ]]; do
            local line=$((record_idx * ${#__record[@]}))
            local source=${lines[$((line + __record_offset["source"]))]}
            local target=${lines[$((line + __record_offset["target"]))]}
            local hash=${lines[$((line + __record_offset["hash"]))]}
            local asroot=${lines[$((line + __record_offset["asroot"]))]}

            if [[ $hash != "directory" && ! -e "$source" ]]; then
                records_to_remove[$record_idx]=1
                info "$source --> $target invalid, removing ..."
                if $asroot; then
                    identity="asroot"
                else
                    identity="asuser"
                fi
                if [[ "$hash" == "symlink" ]]; then
                    install_type="symlink"
                else
                    install_type="file"
                fi
                __remove_handle_old_record "$1" "$install_type" "$source" "$target" "$identity" "skiprec"
            fi
            ((++record_idx))
        done
    fi

    # write back to file
    : >|"$1/.DINFO"
    record_idx=0
    while [[ $((record_idx * ${#__record[@]})) -lt "${#lines[@]}" ]]; do
        local line=$((record_idx * ${#__record[@]}))
        if [[ -z ${records_to_remove["$record_idx"]} ]]; then
            for offset in $(seq 0 "$(("${#__record[@]}" - 1))"); do
                echo "${lines["$((line + offset))"]}" >>"$1/.DINFO"
            done
        fi
        ((++record_idx))
    done
}

# remove all entires in .DINFO ifle, remove associated targets
# $1: directory of the .DINFO file
purge() {
    info "purging $1/.DINFO ..."
    if [[ -f "$1/.DINFO" ]]; then
        local lines
        mapfile -t lines <"$1/.DINFO"
        record_idx=0
        while [[ $((record_idx * ${#__record[@]})) -lt "${#lines[@]}" ]]; do
            local line=$((record_idx * ${#__record[@]}))
            local source=${lines[$((line + __record_offset["source"]))]}
            local target=${lines[$((line + __record_offset["target"]))]}
            local hash=${lines[$((line + __record_offset["hash"]))]}
            local asroot=${lines[$((line + __record_offset["asroot"]))]}

            if [[ $hash == "directory" ]]; then
                if $asroot; then
                    sudo rmdir -p "$target"
                else
                    rmdir -p "$target"
                fi
                info "${target/%\//}/ removed"
            else
                if $asroot; then
                    identity="asroot"
                else
                    identity="asuser"
                fi
                if [[ "$hash" == "symlink" ]]; then
                    local install_type="symlink"
                else
                    local install_type="file"
                fi
                __remove_handle_old_record "$1" "$install_type" "$source" "$target" "$identity" "skiprec"
            fi
            ((++record_idx))
        done
    fi

    if [[ -f $1/.DINFO ]]; then rm "$1/.DINFO"; fi
}
