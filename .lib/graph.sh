#!/bin/bash
# shellcheck disable=SC2178
# shellcheck disable=SC2139

declare __GRAPH_COUNTER
# $1 Graph name
Graph:new() {
    if [[ -n ${!1} ]]; then
        error "Variable '$1' already exists"
        return 1
    fi

    ((++__GRAPH_COUNTER))
    declare -g "$1"="$__GRAPH_COUNTER"

    declare -gA "__GRAPH_NODES_${!1}"
    declare -ga "__GRAPH_ITEMS_${!1}"
    declare -ga "__GRAPH_EDGES_${!1}"
}

# $1: Graph name
Graph:del() {
    unset "__GRAPH_NODES_${!1}"
    unset "__GRAPH_ITEMS_${!1}"
    unset "__GRAPH_EDGES_${!1}"
}

# $1: Graph name
# $2: Node name
# $3: Node value
Graph:addNode() {
    local -n nodes=__GRAPH_NODES_${!1}
    local -n items=__GRAPH_ITEMS_${!1}

    if [[ ${nodes[$2]} ]]; then
        error "Node '$2' already in graph '$1'"
        return 1
    fi

    nodes["$2"]="${#nodes[@]}"
    items+=("$3")
}

# $1: Graph name
# $2: Node name
Graph:hasNode() {
    local -n nodes=__GRAPH_NODES_${!1}
    [[ -n ${nodes[$2]} ]]
}

# $1: Graph id
# $2: Node from
# $3: Node to
#
# nothing will happen if edge already exists
Graph:addEdge() {
    local -n nodes="__GRAPH_NODES_${!1}"
    local -n edges="__GRAPH_EDGES_${!1}"

    if [[ -z ${nodes[$2]} ]]; then
        error "Node '$2' does not exist in graph '$1'"
        return 1
    elif [[ -z ${nodes[$3]} ]]; then
        error "Node '$3' does not exist in graph '$1'"
        return 1
    fi

    local fromIdx=${nodes[$2]}
    local toIdx=${nodes[$3]}

    local -A nextNodes
    eval "nextNodes=(${edges[$fromIdx]})"
    nextNodes[$toIdx]=1
    edges[$fromIdx]="$(printf "[%q]=1 " "${!nextNodes[@]}")"
}
