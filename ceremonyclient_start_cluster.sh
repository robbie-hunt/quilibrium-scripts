#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

# Gracefully exit node when script is stopped
KILL_PROCESS_func() {
    echo "ceremonyclient_start_cluster.sh info: Exiting the node gracefully..."
    pkill -SIGINT -P $$
    wait
    exit 0
}

trap KILL_PROCESS_func SIGINT

USAGE_func() {
    echo ""
    echo "Runs the Quilibrium cluster."
    echo ""
    echo "USAGE: bash ceremonyclient_start_cluster.sh [-h] [-x] [-q] [--core-index-start] [--data-worker-count]"
    echo ""
    echo "       -h                     Display this help dialogue."
    echo "       -x                     For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q                     Quiet mode."
    echo "       --tailscale            Script will make sure tailscale is connected before starting node processes."
    echo "       --core-index-start     Cluster core index start."
    echo "       --data-worker-count    Cluster data worker count."
    echo ""
    exit 0
}

VALIDATE_START_CORE_INDEX_func() {
    # Validate the START_CORE_INDEX input
    if ! [[ "$START_CORE_INDEX" =~ ^[0-9]+$ ]]; then
        echo "ceremonyclient_start_cluster.sh error: --core-index-start must be a non-negative integer."
        exit 1
    fi
    echo "ceremonyclient_start_cluster.sh info: Validated --core-index-start."
}

DETERMINE_GOMAXPROCES_func() {
    # Determine GOMAXPROCS
    if [[ "$RELEASE_OS" == "darwin" ]]; then
        MAX_CORES=$(sysctl -n hw.logicalcpu)
    elif [[ "$RELEASE_OS" == "linux" ]]; then
        MAX_CORES=$(nproc)
    fi
}

VALIDATE_DATA_WORKER_COUNT_func() {
    # Validate the DATA_WORKER_COUNT input
    if ! [[ "$DATA_WORKER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo "ceremonyclient_start_cluster.sh error: --data-worker-count must be a positive integer."
        exit 1
    fi
    # If DATA_WORKER_COUNT is greater than MAX_CORES, set it to MAX_CORES
    if [ "$DATA_WORKER_COUNT" -gt "$MAX_CORES" ]; then
        DATA_WORKER_COUNT=$MAX_CORES
        echo "ceremonyclient_start_cluster.sh info: --data-worker-count adjusted down to maximum (MAX_CORES): $DATA_WORKER_COUNT."
    fi
    echo "ceremonyclient_start_cluster.sh info: Validated --data-worker-count."
}

CHECK_IF_MASTER_NODE_func() {
    # Adjust DATA_WORKER_COUNT if START_CORE_INDEX is 1
    if [ "$START_CORE_INDEX" -eq 1 ]; then
        MASTER_NODE=1
        # Adjust MAX_CORES if START_CORE_INDEX is 1
        echo "ceremonyclient_start_cluster.sh info: This is a master node. Adjusting max cores available to $((MAX_CORES - 1)) (from $MAX_CORES) due to starting the master node on core 0."
        MAX_CORES=$((MAX_CORES - 1))
    fi
}

GATHER_WORKER_IPS_func() {
    awk '/dataWorkerMultiaddrs:/ {in_block=1; next} in_block && /^[^[:space:]-]/ {exit} in_block {print}' $NODE_CONFIG_FILE \
    | grep "^  - .*" \
    | awk '{ if ($0 ~ /\/ip4\//) { n = split($0, arr, "/"); ip = arr[3]; comment = substr($0, index($0, "#") + 2); if (!(ip in seen)) { seen[ip] = comment } } } END { for (ip in seen) { print ip " - " seen[ip] } }'
}

CHECK_TAILSCALE_func() {
    if [[ $(tailscale status) == "Tailscale is stopped." ]]; then
        echo "ceremonyclient_start_cluster.sh error: Tailscale is not running. Please connect Tailscale."
        exit 1
    else
        if [[ $MASTER_NODE == 1 ]]; then
            IP_ADDRESSES_TO_PING=$(GATHER_WORKER_IPS_func | grep -v " - Master.*")
        else
            IP_ADDRESSES_TO_PING=$(GATHER_WORKER_IPS_func | grep " - Master.*")
        fi
        for IP_ADDRESS_TO_PING in $IP_ADDRESSES_TO_PING; do
            echo "IP_ADDRESS_TO_PING: $IP_ADDRESS_TO_PING"
            IP_ADDRESS=$(echo "$IP_ADDRESS_TO_PING" | awk -F' - ' '{print $1}')
            MACHINE_INFO=$(echo "$IP_ADDRESS_TO_PING" | awk -F' - ' '{print $2}')
            echo "IP_ADDRESS: $IP_ADDRESS"
            echo "MACHINE_INFO: $MACHINE_INFO"
            if [[ $(tailscale ping $IP_ADDRESS 2>/dev/null) ]]; then
                echo "ceremonyclient_start_cluster.sh info: Successful Tailscale ping to node $IP_ADDRESS ($MACHINE_INFO)."
            else
                if [[ $MASTER_NODE == 1 ]]; then
                    echo "ceremonyclient_start_cluster.sh error: Tailscale could not connect to node $IP_ADDRESS ($MACHINE_INFO). Continuing..."
                else
                    echo "ceremonyclient_start_cluster.sh error: Tailscale could not connect to node $IP_ADDRESS ($MACHINE_INFO). Exiting..."
                    exit 1
                fi
            fi
        done
    fi
}

# Function to start the master node up if this is master node
START_MASTER_func() {
    echo "ceremonyclient_start_cluster.sh info: Starting master node..."
    $QUIL_NODE_PATH/$NODE_BINARY &
    MASTER_PID=$!
}

# Function to start the data workers if this is a worker node
# Loops through the data worker count and start each core
START_WORKERS_func() {
    echo "ceremonyclient_start_cluster.sh info: Starting worker nodes..."
    # start the master node
    for ((i=0; i<DATA_WORKER_COUNT; i++)); do
        CORE=$((START_CORE_INDEX + i))
        echo "ceremonyclient_start_cluster.sh info: Starting core $CORE."
        $QUIL_NODE_PATH/$NODE_BINARY --core $CORE --parent-process $PARENT_PID &
    done
}

# Function to check if the master process is running
# Returns exit status of ps command
IS_MASTER_PROCESS_RUNNING_func() {
    ps -p $MASTER_PID > /dev/null 2>&1
    return $?
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

RELEASE_ARCH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

START_CORE_INDEX=1

MASTER_NODE=0

if [[ "$RELEASE_OS" == "darwin" ]]; then
    DATA_WORKER_COUNT=$(sysctl -n hw.logicalcpu)
elif [[ "$RELEASE_OS" == "linux" ]]; then
    DATA_WORKER_COUNT=$(nproc)
fi

PARENT_PID=$$

TAILSCALE=0

QUIET=0

# Some variables for node paths and binaries
QUIL_NODE_PATH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_node_dir')
NODE_CONFIG_DIR=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_config_dir')
NODE_CONFIG_FILE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_config')
NODE_BINARY_NAME=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet' | awk -F'/' '{print $NF}')
NODE_BINARY="$NODE_BINARY_NAME --config $NODE_CONFIG_DIR"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -x)
            set -x
            shift 1
            ;;
        -h)
            USAGE_func
            exit 0
            ;;
        -q)
            QUIET=1
            shift 1
            ;;
        --core-index-start)
            START_CORE_INDEX="$2"
            shift 2
            ;;
        --data-worker-count)
            DATA_WORKER_COUNT="$2"
            shift 2
            ;;
        --tailscale)
            TAILSCALE=1
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

DETERMINE_GOMAXPROCES_func
VALIDATE_START_CORE_INDEX_func
VALIDATE_DATA_WORKER_COUNT_func

CHECK_IF_MASTER_NODE_func
if [[ $TAILSCALE == 1 ]]; then
    CHECK_TAILSCALE_func
else
    :
fi

exit 0

MASTER_PID=0

# kill off any stragglers
pkill node-*

if [ $START_CORE_INDEX -eq 1 ]; then
    START_MASTER_func
fi

START_WORKERS_func

while true
do
  # we only care about restarting the master process because the cores should be alive
  # as long as this file is running (and this will only run on the machine with a start index of 1)
  if [ $START_CORE_INDEX -eq 1 ] && ! IS_MASTER_PROCESS_RUNNING_func; then
    echo "ceremonyclient_start_cluster.sh error: Process crashed or stopped; restarting..."
    START_MASTER_func
  fi
  sleep 440
done