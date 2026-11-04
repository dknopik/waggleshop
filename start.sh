#!/usr/bin/env bash
# Starts several nodes on localhost, connected in a full mesh or a line, and
# prefixes each node's output with its name. Lines typed into the script go to
# the stdin of the node they name. Ctrl-C stops them all.
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 [-p BASE_PORT] <mesh|line> [NODES] [-- NODE_ARGS...]

Starts NODES nodes (default 4), listening on BASE_PORT (default 9000) and up.

  mesh  every node connects to every other node
  line  every node connects to the one before it

Arguments after -- are passed to every node.

Lines typed while the nodes run go to the stdin of node 0. Start a line with a
node's number to send the rest of it to that node: "3 hello" sends "hello" to
node 3.
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

# Sends every line read to the node it names: "3 hello" sends "hello" to node
# 3, and a line without a number goes to node 0 unchanged.
forward_input() {
    local line target text
    # When started with `&`, reading the terminal would suspend the script and
    # all nodes. Ignoring the signal makes the read fail instead.
    trap '' TTIN
    while IFS= read -r line; do
        target=0 text=$line
        if [[ $line =~ ^([0-9]+)[[:space:]]+(.*)$ ]]; then
            target=${BASH_REMATCH[1]} text=${BASH_REMATCH[2]}
        fi
        if [[ ! -p $inputs/$target ]]; then
            echo "no node $target" >&2
        elif ! kill -0 "${pids[target]}" 2>/dev/null; then
            echo "node $target has exited" >&2
        else
            printf '%s\n' "$text" 1<>"$inputs/$target"
        fi
    done
}

inputs=$(mktemp -d)
pids=()
trap 'rm -rf "$inputs"; kill ${pids[@]+"${pids[@]}"} ${forwarder:-} 2>/dev/null' EXIT
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

    # The node's stdin is a FIFO. Opening it read-write means the node never
    # sees EOF, however often forward_input opens and closes its end. Opening
    # it here, not in the node's redirections, means it is open before any
    # input arrives, which would otherwise be lost.
    mkfifo "$inputs/$i"
    exec 3<>"$inputs/$i"
    "$bin" "${args[@]}" "$@" <&3 3<&- > >(prefix "$label ") 2>&1 &
    pids+=($!)
    exec 3<&-
done

# In the background, so that the script still ends once all nodes have exited.
# Without the redirection, a background job's stdin is /dev/null.
forward_input <&0 &
forwarder=$!
wait "${pids[@]}" || true
