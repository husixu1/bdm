#!/bin/bash
# shellcheck disable=SC2016

if [[ ${MODE:?} == prepend ]]; then
    template='#!/bin/bash
if [[ ":$PATH:" != *":'"${PATH_TO_ADD:?}"':"* ]]; then
    export PATH="'"${PATH_TO_ADD:?}"':$PATH"
fi'
elif [[ ${MODE:?} == append ]]; then
    template='#!/bin/bash
if [[ ":$PATH:" != *":'"${PATH_TO_ADD:?}"':"* ]]; then
    export PATH="$PATH:'"${PATH_TO_ADD:?}"'"
fi'
fi

echo "$template"
