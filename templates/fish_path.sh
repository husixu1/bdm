#!/bin/bash
# shellcheck disable=SC2016

if [[ ${MODE:?} == prepend ]]; then
    template='#!/usr/bin/fish
if not contains "'"${PATH_TO_ADD:?}"'" $PATH
    set -x PATH "'"${PATH_TO_ADD:?}"'" $PATH
end'
elif [[ ${MODE:?} == append ]]; then
    template='#!/usr/bin/fish
if not contains "'"${PATH_TO_ADD:?}"'" $PATH
    set -x PATH $PATH "'"${PATH_TO_ADD:?}"'"
end'
fi

echo "$template"
