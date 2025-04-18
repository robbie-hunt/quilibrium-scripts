#!/bin/bash

set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

# Gracefully exit node when script is stopped
kill_process() {
    pkill -SIGINT -P $$
    wait
    exit 0
}

trap kill_process SIGINT

# Figure out what directory I'm in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$QUIL_SCRIPTS_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
QUIL_SCRIPTS_DIR="/Users/robbie/.scripts/quilibrium-scripts"
QUIL_SCRIPTS_PARENT_DIR=$(echo "$QUIL_SCRIPTS_DIR" | awk -F'/' 'BEGIN{OFS=FS} {$NF=""; print}' | sed 's/\/*$//')

RELEASE_ARCH=$(bash $QUIL_SCRIPTS_DIR/tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $QUIL_SCRIPTS_DIR/tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

START_CORE_INDEX=1
if [[ "$RELEASE_OS" == "darwin" ]]; then
    DATA_WORKER_COUNT=$(sysctl -n hw.logicalcpu)
elif [[ "$RELEASE_OS" == "linux" ]]; then
    DATA_WORKER_COUNT=$(nproc)
fi
PARENT_PID=$$

# Some variables for paths and binaries
QUIL_NODE_PATH=$(bash $QUIL_SCRIPTS_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_node_dir')
NODE_CONFIG_DIR=$(bash $QUIL_SCRIPTS_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_config_dir')
NODE_BINARY_NAME=$(bash $QUIL_SCRIPTS_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet' | awk -F'/' '{print $NF}')
NODE_BINARY="$NODE_BINARY_NAME"

echo "NODE BINARY $NODE_BINARY"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --core-index-start)
            START_CORE_INDEX="$2"
            shift 2
            ;;
        --data-worker-count)
            DATA_WORKER_COUNT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done


# Validate START_CORE_INDEX
if ! [[ "$START_CORE_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Error: --core-index-start must be a non-negative integer"
    exit 1
fi

# Validate DATA_WORKER_COUNT
if ! [[ "$DATA_WORKER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --data-worker-count must be a positive integer"
    exit 1
fi

if [[ "$RELEASE_OS" == "darwin" ]]; then
    MAX_CORES=$(sysctl -n hw.logicalcpu)
elif [[ "$RELEASE_OS" == "linux" ]]; then
    MAX_CORES=$(nproc)
fi

# Adjust DATA_WORKER_COUNT if START_CORE_INDEX is 1
if [ "$START_CORE_INDEX" -eq 1 ]; then
    # Adjust MAX_CORES if START_CORE_INDEX is 1
    echo "Adjusting max cores available to $((MAX_CORES - 1)) (from $MAX_CORES) due to starting the master node on core 0"
    MAX_CORES=$((MAX_CORES - 1))
fi

# If DATA_WORKER_COUNT is greater than MAX_CORES, set it to MAX_CORES
if [ "$DATA_WORKER_COUNT" -gt "$MAX_CORES" ]; then
    DATA_WORKER_COUNT=$MAX_CORES
    echo "DATA_WORKER_COUNT adjusted down to maximum: $DATA_WORKER_COUNT"
fi

MASTER_PID=0

# kill off any stragglers
pkill node-*



# Function to start the master node up if this is master node
start_master() {
    $QUIL_NODE_PATH/$NODE_BINARY --config $NODE_CONFIG_DIR &
    MASTER_PID=$!
}

if [ $START_CORE_INDEX -eq 1 ]; then
    start_master
fi

# Function to start the data workers if this is a worker node
# Loops through the data worker count and start each core
start_workers() {
    # start the master node
    for ((i=0; i<DATA_WORKER_COUNT; i++)); do
        CORE=$((START_CORE_INDEX + i))
        echo "Starting core $CORE"
        $QUIL_NODE_PATH/$NODE_BINARY --core $CORE --parent-process $PARENT_PID --config $NODE_CONFIG_DIR &
    done
}

is_master_process_running() {
    ps -p $MASTER_PID > /dev/null 2>&1
    return $?
}

start_workers

while true
do
  # we only care about restarting the master process because the cores should be alive
  # as long as this file is running (and this will only run on the machine with a start index of 1)
  if [ $START_CORE_INDEX -eq 1 ] && ! is_master_process_running; then
    echo "Process crashed or stopped. restarting..."
    start_master
  fi
  sleep 440
done