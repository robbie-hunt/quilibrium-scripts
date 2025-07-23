#!/bin/bash

# Set shell options
set -ou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Toolset for debugging/running a Quilibrium cluster."
    echo ""
    echo "USAGE: bash ceremonyclient_cluster_tools.sh [-h] [-x] [-q] [-g master/slaves]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q    Quiet mode."
    echo "       -g    Gather IPs and information of worker nodes in cluster."
    echo ""
    exit 0
}

GATHER_WORKER_IPS_func() {
    awk '/dataWorkerMultiaddrs:/ {in_block=1; next} in_block && /^[^ ]/ {in_block=0} in_block && /^  -/ {print}' $NODE_CONFIG_FILE \
    | grep "^  - .*" \
    | awk '{ if ($0 ~ /\/ip4\//) { n = split($0, arr, "/"); ip = arr[3]; comment = substr($0, index($0, "#") + 2); if (!(ip in seen)) { seen[ip] = comment } } } END { for (ip in seen) { print ip " - " seen[ip] } }'
}

CHECK_TAILSCALE_HARDCODING_func() {
    if tailscale version &>/dev/null; then
        :
    else
        if /usr/local/bin/tailscale version &>/dev/null; then
            TAILSCALE_PATH_NEEDS_TO_BE_HARDCODED=1
        else
            echo "ceremonyclient_cluster_tools.sh error [$(date)]: Tailscale is not available in the CLI."
            echo "Either install the Tailscale CLI via the Tailscale Settings, or run"
            echo "'which tailscale' and hardcode the correct tailscale path into this script."
        fi
    fi
}

CHECK_TAILSCALE_STATUS_func() {
    if [[ $TAILSCALE_PATH_NEEDS_TO_BE_HARDCODED == 1 ]]; then
        TAILSCALE_STATUS_RESULT=$(/usr/local/bin/tailscale status)
    else
        TAILSCALE_STATUS_RESULT=$(tailscale status)
    fi
    if [[ $TAILSCALE_STATUS_RESULT == "Tailscale is stopped." ]]; then
        TAILSCALE_NOT_RUNNING=1
        echo "ceremonyclient_cluster_tools.sh warning [$(date)]: Tailscale is not running."
    else
        TAILSCALE_NOT_RUNNING=0
        break  # success, exit the loop
    fi
}

CHECK_TAILSCALE_PING_func() {
    if [[ -z "$1" ]]; then
        IP_ADDRESSES_TOTAL=$(GATHER_WORKER_IPS_func)
        if [[ $MASTER_NODE == 1 ]]; then
            IP_ADDRESSES_TO_PING=$(echo "$IP_ADDRESSES_TOTAL" | grep -v " - Master.*")
        else
            IP_ADDRESSES_TO_PING=$(echo "$IP_ADDRESSES_TOTAL" | grep " - Master.*")
        fi
    else
        IP_ADDRESSES_TO_PING="$1"
    fi

    while IFS= read -r IP_ADDRESS_TO_PING; do
        IP_ADDRESS=$(echo "$IP_ADDRESS_TO_PING" | awk -F' - ' '{print $1}')
        MACHINE_INFO=$(echo "$IP_ADDRESS_TO_PING" | awk -F' - ' '{print $2}')
        if [[ $TAILSCALE_PATH_NEEDS_TO_BE_HARDCODED == 1 ]]; then
            TAILSCALE_PING_RESULT=$(/usr/local/bin/tailscale ping -c 1 $IP_ADDRESS 2>/dev/null)
        else
            TAILSCALE_PING_RESULT=$(tailscale ping -c 1 $IP_ADDRESS 2>/dev/null)
        fi
        if [[ $TAILSCALE_PING_RESULT == "pong"* ]]; then
            echo "ceremonyclient_cluster_tools.sh info [$(date)]: Tailscale successfully pinged node $IP_ADDRESS ($MACHINE_INFO)."
        else
            if [[ $CONTINUE_IF_TAILSCALE_PING_FAILS == 1 ]]; then
                echo "ceremonyclient_cluster_tools.sh warning [$(date)]: Tailscale could not connect to node $IP_ADDRESS ($MACHINE_INFO). Continuing anyway..."
            else
                echo "ceremonyclient_cluster_tools.sh error [$(date)]: Tailscale could not connect to node $IP_ADDRESS ($MACHINE_INFO)."
                return 1
            fi
        fi
    done <<< "$IP_ADDRESSES_TO_PING"
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

USING_TAILSCALE=0
TAILSCALE_PATH_NEEDS_TO_BE_HARDCODED=0

MASTER_NODE=0

while getopts "xhqtg" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        t) USING_TAILSCALE=1;;
        g) GATHER_WORKER_IPS_func; exit;;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

if [[ "$TAILSCALE" == 1 ]]; then
    MACHINE_IP=$(tailscale ip | head -1)
else
    MACHINE_IP=$(curl -s ifconfig.me | tr -d '\n')
fi
MASTER_IP=$(GATHER_WORKER_IPS_func | grep "Master")
SLAVE_IPS=$(GATHER_WORKER_IPS_func | grep -v "Master")

if [[ $(echo "$MASTER_IP" | grep "$MACHINE_IP") ]]; then
    MASTER_NODE=1
else
    MASTER_NODE=0
fi

CURRENT_NETSTAT_CONNECTIONS=$(netstat -n)
if [[ "$MASTER_NODE" == 1 ]]; then
    # Check if this master can ping each slave node
    for SLAVE_IP in $SLAVE_IPS; do
        if CHECK_TAILSCALE_PING_func "$SLAVE_IP"; then
            :
        fi
        
    done
    # Check if this master is currently connected to each slave node
else
    # Check if this slave can ping master
    # Check if this slave is currently connected to master
fi

exit