#!/bin/bash

# Set shell options
set -ou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Toolset for debugging/running a Quilibrium cluster."
    echo ""
    echo "USAGE: bash ceremonyclient_cluster_tools.sh [-h] [-x] [-q]"
    echo ""
    echo "       -h                                   Display this help dialogue."
    echo "       -x                                   For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q                                   Quiet mode."
    echo ""
    exit 0
}

GATHER_WORKER_IPS_func() {
    awk '/dataWorkerMultiaddrs:/ {in_block=1; next} in_block && /^[^ ]/ {in_block=0} in_block && /^  -/ {print}' $NODE_CONFIG_FILE \
    | grep "^  - .*" \
    | awk '{ if ($0 ~ /\/ip4\//) { n = split($0, arr, "/"); ip = arr[3]; comment = substr($0, index($0, "#") + 2); if (!(ip in seen)) { seen[ip] = comment } } } END { for (ip in seen) { print ip " - " seen[ip] } }'
}

# Figure out what directory I'm in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SCRIPT_PARENT_DIR=$(echo "$SCRIPT_DIR" | awk -F'/' 'BEGIN{OFS=FS} {$NF=""; print}' | sed 's/\/*$//')

RELEASE_ARCH=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

QUIET=0

# Some variables for node paths and binaries
QUIL_NODE_PATH=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -key 'ceremonyclient_node_dir')
NODE_CONFIG_DIR=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -key 'ceremonyclient_config_dir')
NODE_CONFIG_FILE=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -key 'ceremonyclient_config')
NODE_BINARY_NAME=$(bash $SCRIPT_DIR/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet' | awk -F'/' '{print $NF}')
NODE_BINARY="$NODE_BINARY_NAME --config $NODE_CONFIG_DIR"

while getopts "xhq" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

GATHER_WORKER_IPS_func

exit