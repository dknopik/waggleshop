#!/usr/bin/env bash
# Starts several nodes on localhost, connected in a full mesh or a line, and
# prefixes each node's output with its name. Ctrl-C stops them all.
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 [-p BASE_PORT] <mesh|line> [NODES] [-- NODE_ARGS...]

Starts NODES nodes (default 4), listening on BASE_PORT (default 9000) and up.

  mesh  every node connects to every other node
  line  every node connects to the one before it

Arguments after -- are passed to every node.
EOF
}

base_port=9000
while getopts "p:h" opt; do
    case $opt in
        p) base_port=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

topology=${1:-}
case $topology in
    mesh | line) shift ;;
    *) usage >&2; exit 1 ;;
esac
nodes=4
if [[ $# -gt 0 && $1 != -- ]]; then
    nodes=$1
    shift
fi
if [[ $# -gt 0 ]]; then
    if [[ $1 != -- ]]; then
        usage >&2
        exit 1
    fi
    shift
fi
if ! [[ $nodes =~ ^[1-9][0-9]*$ && $base_port =~ ^[1-9][0-9]*$ ]]; then
    echo "NODES and BASE_PORT must be positive numbers" >&2
    exit 1
fi

root=$(cd "$(dirname "$0")" && pwd)
cargo build --manifest-path "$root/Cargo.toml"
bin=${CARGO_TARGET_DIR:-$root/target}/debug/waggle-workshop

# Prefixes every line read with `$1`.
prefix() {
    awk -v p="$1" '{ print p $0; fflush() }'
}

pids=()
trap 'kill ${pids[@]+"${pids[@]}"} 2>/dev/null' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

colors=(31 32 33 34 35 36)
width=${#nodes}
for ((i = 0; i < nodes; i++)); do
    args=(-l $((base_port + i)))
    peers=
    if [[ $topology == mesh ]]; then
        for ((j = 0; j < i; j++)); do
            peers+=${peers:+,}$((base_port + j))
        done
    elif ((i > 0)); then
        peers=$((base_port + i - 1))
    fi
    if [[ -n $peers ]]; then
        args+=(-c "$peers")
    fi

    printf -v label "node%-${width}s |" "$i"
    if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
        label=$'\e['"${colors[i % ${#colors[@]}]}m$label"$'\e[0m'
    fi
    echo "$label waggle-workshop ${args[*]}${*:+ $*}"
    "$bin" "${args[@]}" "$@" > >(prefix "$label ") 2>&1 &
    pids+=($!)
done

wait
