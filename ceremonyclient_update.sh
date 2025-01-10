# #!/bin/bash

# Set shell options
set -eou pipefail
set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Updates the Quilibrium node binaries (including qclient) to latest versions, and restarts node daemons."
    echo ""
    echo "USAGE: bash ceremonyclient_update.sh [-h] ] [-x] [-c]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -c    This node is part of a cluster."
    echo "             (By default this is set to null, meaning this node is run as a standalone node.)"
    echo "       -d    (Optional) Directory to update binaries in."
    echo "             By default, the directory for updates is determined by the 'ceremonyclient_node_dir' key in .localenv."
    echo ""
    exit 0
}

# Figure out what directory I'm in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SCRIPT_ROOT_DIR=$(echo "$SCRIPT_DIR" | awk -F'/' 'BEGIN{OFS=FS} {$NF=""; print}' | sed 's/\/*$//')

# Compare the currently installed binary with the latest available binary from release
COMPARE_VERSIONS_func() {
    local FILE_INSTALLED=$(echo $1 | awk -F'/' '{print $NF}' | xargs)
    local FILE_INSTALLED_PATH="$1"
    local FILE_RELEASE="$2"

    echo "FILE_INSTALLED: $FILE_INSTALLED"
    echo "FILE_INSTALLED_PATH: $FILE_INSTALLED_PATH"
    echo "FILE_RELEASE: $FILE_RELEASE"

    if [[ "$FILE_INSTALLED" == "$FILE_RELEASE" ]]; then
        echo "$FILE_INSTALLED file installed is the latest version, no need to update."
    else
        echo "Update required for $FILE_INSTALLED."
        . $SCRIPT_DIR/tools/ceremonyclient_download.sh -f "$FILE_RELEASE"
    fi
}

# Update either the start_cluster script or the actual service file with the new node binary, depending on whether -c was used
UPDATE_SERVICE_FILE_func() {
    NEW_LATEST_NODE_FILE_INSTALLED_PATH=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
    NEW_LATEST_NODE_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_NODE_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)

    # If cluster, update start_cluster script
    if [[ $CLUSTER == 1 ]]; then
        sed -i "s/NODE_BINARY\=[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    # If not cluster, then
    else
        # If macOS, update launchctl plist file
        if [[ "$RELEASE_OS" == "darwin" ]]; then
            sudo sed -i "s/node-[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
        # If Linux, update systemctl service file
        elif [[ "$RELEASE_OS" == "linux" ]]; then
            sed -i "/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH" /lib/systemd/system/ceremonyclient.service
        fi
    fi
}

ALTER_RELOAD_RESTART_DAEMONS_func() {
    # If macOS, then update launchctl plist file and restart service
    # Using launchctl commands 'bootout' and 'bootstrap' instead of the deprecated 'load' and 'unload' commands
    if [[ "$RELEASE_OS" == "darwin" ]]; then
        # Disable and unload the service
        sudo launchctl disable system/local.ceremonyclient
        sleep 2
        sudo launchctl bootout system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2

        UPDATE_SERVICE_FILE_func

        # Enable, load and start service
        sudo launchctl enable system/local.ceremonyclient
        sleep 2
        sudo launchctl bootstrap system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2
        # Use kickstart with the -k flag to kill any currently running ceremonyclient services,
        # and -p flag to print the PID of the service that starts up
        # This ensures only one ceremonyclient service running
        launchctl kickstart -kp system/local.ceremonyclient

        # Let service sit for 60s, then print out the logfile
        echo "ceremonyclient updated and restarted. Waiting 60s before printing a status read from the ceremonyclient daemon."
        sleep 60
        tail -F "$CEREMONYCLIENT_LOGFILE"
    # If Linux, then update systemctl service file and restart service
    elif [[ "$RELEASE_OS" == "linux" ]]; then
        systemctl stop ceremonyclient
        sleep 2

        UPDATE_SERVICE_FILE_func

        # Enable, load and start service
        systemctl daemon-reload
        sleep 2
        systemctl restart ceremonyclient

        # Let service sit for 60s, then print out the logfile
        echo "ceremonyclient daemon updated and reloaded. Waiting 60s before printing a status read from the ceremonyclient daemon."
        sleep 60
        systemctl status ceremonyclient
    fi
}

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

# Set to 1 by using the -c flag; indicates that this node is running as part of a cluster
# This simply means that when it comes to updating daemon/service files, this script will update the
# ceremonyclient_start_cluster.sh script with the new node filename, and not the daemon/service file.
CLUSTER=0

# Supply a node directory using the -d flag
DIRECTORY=0

while getopts "xhqcd:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        c) CLUSTER=1;;
        d) DIRECTORY="$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

if $(. $SCRIPT_DIR/tools/ceremonyclient_check_localenv.sh -q); then
    :
else
    . $SCRIPT_DIR/tools/ceremonyclient_check_localenv.sh
    exit 1
fi

# The OS of the machine running this script
RELEASE_OS=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
# The release line ('os-arch') of the machine running this script
RELEASE_LINE=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -release-line)

# For the ceremonyclient node directory
# If a directory was supplied via the -d option, use it
# Otherwise, use the directory in the .localenv
if [[ $DIRECTORY == 0 ]]; then
    CEREMONYCLIENT_NODE_DIR=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_node_dir")
else
    CEREMONYCLIENT_NODE_DIR="$DIRECTORY"
fi

# Logfile location
CEREMONYCLIENT_LOGFILE="$HOME/ceremonyclient.log"

# Get the latest version of the main node and qclient binaries,
# both installed and available in release
LATEST_NODE_INSTALLED=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
LATEST_NODE_RELEASE=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
LATEST_QCLIENT_INSTALLED=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-installed-files-quiet')
LATEST_QCLIENT_RELEASE=$(. $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-files-quiet')

COMPARE_VERSIONS_func "$LATEST_NODE_INSTALLED" "$LATEST_NODE_RELEASE"
COMPARE_VERSIONS_func "$LATEST_QCLIENT_INSTALLED" "$LATEST_QCLIENT_RELEASE"

ALTER_RELOAD_RESTART_DAEMONS_func

exit 0