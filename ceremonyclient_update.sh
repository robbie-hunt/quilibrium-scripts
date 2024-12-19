#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

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

COMPARE_VERSIONS_func() {
    local FILE_INSTALLED=$(echo "$1" | awk -F'/' '{print $NF}' | xargs)
    local FILE_INSTALLED_PATH="$1"
    local FILE_RELEASE="$2"

    if [[ "$FILE_INSTALLED" == "$FILE_RELEASE" ]]; then
        echo "$FILE_INSTALLED file installed is the latest version, no need to update."
    else
        echo "Update required for $FILE_INSTALLED."
        #FETCH_FILES_func "$FILE_RELEASE"
        ./tools/ceremonyclient_download.sh -f "$FILE_RELEASE"
    fi
}

UPDATE_DAEMON_FILE_func() {
    if [[ $CLUSTER == 1 ]]; then
        # Update start_cluster script
        sed -i "s/NODE_BINARY\=[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
        # sed "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    else
        if [[ "$RELEASE_OS" == "darwin" ]]; then
            # Update launchctl plist file
            sudo sed -i "s/node-[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
            # sudo sed "s/node-[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
        elif [[ "$RELEASE_OS" == "linux" ]]; then
            # Update systemctl service file
            sed -i "/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH" /lib/systemd/system/ceremonyclient.service
            # sed "/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH" /lib/systemd/system/ceremonyclient.service
        fi
    fi
}

ALTER_RELOAD_RESTART_DAEMONS_func() {
    if [[ "$RELEASE_OS" == "darwin" ]]; then
        sudo launchctl disable system/local.ceremonyclient
        sleep 2
        sudo launchctl bootout system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2

        UPDATE_DAEMON_FILE_func

        sudo launchctl enable system/local.ceremonyclient
        sleep 2
        sudo launchctl bootstrap system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2
        launchctl kickstart -kp system/local.ceremonyclient

        echo "ceremonyclient updated and restarted. Waiting 60s before printing a status read from the ceremonyclient daemon."
        sleep 60
        tail -F /Users/robbie/ceremonyclient.log
    elif [[ "$RELEASE_OS" == "linux" ]]; then
        systemctl stop ceremonyclient
        sleep 2

        UPDATE_DAEMON_FILE_func

        systemctl daemon-reload
        sleep 2
        systemctl restart ceremonyclient

        echo "ceremonyclient daemon updated and reloaded. Waiting 60s before printing a status read from the ceremonyclient daemon."
        sleep 60
        systemctl status ceremonyclient
    fi
}



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

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

# Set to 1 by using the -c flag; indicates that this node is running as part of a cluster
# This simply means that when it comes to updating daemon/service files, this script will update the
# ceremonyclient_start_cluster.sh script with the new node filename, and not the daemon/service file.
CLUSTER=0

# The OS of the machine running this script
RELEASE_OS=$(./tools/ceremonyclient_env.sh -os)
# The release line ('os-arch') of the machine running this script
RELEASE_LINE=$(./tools/ceremonyclient_env.sh -release-line)

# For the ceremonyclient node directory
# If a directory was supplied via the -d option, use it
# Otherwise, use the directory in the .localenv
if [[ -z "$DIRECTORY" ]]; then
    CEREMONYCLIENT_NODE_DIR=$(./ceremonyclient_env.sh -key "ceremonyclient_node_dir")
else
    CEREMONYCLIENT_NODE_DIR="$DIRECTORY"
fi

# Get the latest version of the main node and qclient binaries,
# both installed and available in release
LATEST_NODE_INSTALLED=$(./tools/ceremonyclient_env.sh -latest-version 'node-install-files-quiet')
LATEST_NODE_RELEASE=$(./tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
LATEST_QCLIENT_INSTALLED=$(./tools/ceremonyclient_env.sh -latest-version 'qclient-install-files-quiet')
LATEST_QCLIENT_RELEASE=$(./tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')

COMPARE_VERSIONS_func "$LATEST_NODE_INSTALLED" "$LATEST_NODE_RELEASE"
COMPARE_VERSIONS_func "$LATEST_QCLIENT_INSTALLED" "$LATEST_QCLIENT_RELEASE"

ALTER_RELOAD_RESTART_DAEMONS_func

exit 0