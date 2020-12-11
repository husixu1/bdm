#!/bin/bash

# start new transaction
transaction() {
    [[ -z ${_ROLLBACKS+x} ]] || {
        error "Already in transaction"
        return 1
    }
    _ROLLBACKS=("true")
}

#1 transaction name
commit() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Commit when not in transaction"
        return 1
    }
    unset _ROLLBACKS
}

# All rollback command will be executed, even if some of them has non-zero exit status
rollback() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Rollback when not in transaction"
        return 1
    }

    local rollbackCount=${#_ROLLBACKS[@]}
    # execute the rollback stack in reverse
    for ((i = 0; i < rollbackCount; ++i)); do
        local -a rollbackCommand
        eval "rollbackCommand=(${_ROLLBACKS[$((rollbackCount - i - 1))]})"
        "${rollbackCommand[@]}" || {
            error "Rollback command '${rollbackCommand[*]}' failed."
            continue
        }
    done
    unset _ROLLBACKS
}

# params before `---`: action command
# params after `---`: rollback command
#
# If action command failed, rollback command is executed and the return value is 1
action() {
    [[ -z ${_ROLLBACKS+x} ]] && {
        error "Try to perform action when not in transaction"
        return 1
    }

    local actionParamCount=1
    for param in "$@"; do
        [[ ${param} == "---" ]] && break
        ((++actionParamCount))
    done

    # perform action
    "${@:1:$((actionParamCount - 1))}" || {
        error "Action '${*:1:$((actionParamCount - 1))}' failed. Rolling back..."
        rollback && return 1;
    }

    # Add rollback to rollback list only when action succeeds
    # (so rollback for the the last failed action will not be executed)
    _ROLLBACKS+=("$(printf "%q " "${@:$((actionParamCount + 1))}")")
}
