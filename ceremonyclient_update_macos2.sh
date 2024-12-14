#!/bin/bash

echo ""

CLUSTER=0

RELEASE_ARCH=$(./ceremonyclient_env.sh -arch)
RELEASE_OS=$(./ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

CEREMONYCLIENT_NODE_DIR=$(./ceremonyclient_env.sh -key "ceremonyclient_node_dir")

LATEST_VERSIONS=$(./ceremonyclient_env.sh -latest-version 'files-quiet')
LATEST_NODE_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '1q;d')
LATEST_NODE_RELEASE=$(echo "$LATEST_VERSIONS" | sed '2q;d')
LATEST_QCLIENT_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '3q;d')
LATEST_QCLIENT_RELEASE=$(echo "$LATEST_VERSIONS" | sed '4q;d')

## Function to fetch new files
FETCH_FILES_func() {
    local FILE_PATTERN="$1"
    local TYPE="$(echo $FILE_PATTERN | awk -F'-' '{print $1}')_release_url"
    local URL=$(./ceremonyclient_env.sh -key $TYPE)

    # List files in most recent release
    RELEASE_FILES_AVAILABLE=$(curl -s -S $URL | grep $FILE_PATTERN)

    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        echo "Error: no release files relating to $FILE_PATTERN could be found."
        echo "This could be due to network issues."
        exit 1
    fi

    for RELEASE_FILE in $RELEASE_FILES_AVAILABLE; do
#        if curl -s -S "https://releases.quilibrium.com/$RELEASE_FILE" > "$CEREMONYCLIENT_NODE_DIR/$RELEASE_FILE"; then
            echo "Downloaded and installed file: $RELEASE_FILE."
#        fi
    done
}

COMPARE_VERSIONS_func() {
    local FILE_INSTALLED=$(echo "$1" | awk -F'/' '{print $NF}' | xargs)
    local FILE_INSTALLED_PATH="$1"
    local FILE_RELEASE="$2"

    if [[ "$FILE_INSTALLED" == "$FILE_RELEASE" ]]; then
        echo "$FILE_INSTALLED file installed is the latest version, no need to update."
    else
        echo "Update required for $FILE_INSTALLED."
        FETCH_FILES_func "$FILE_RELEASE"
    fi
}

#COMPARE_VERSIONS_func "$LATEST_NODE_INSTALLED" "$LATEST_NODE_RELEASE"
#COMPARE_VERSIONS_func "$LATEST_QCLIENT_INSTALLED" "$LATEST_QCLIENT_RELEASE"
#COMPARE_VERSIONS_func "/Users/robbie/ceremonyclient/node/node-2.0.4-darwin-arm64" "$LATEST_NODE_RELEASE"
#COMPARE_VERSIONS_func "/Users/robbie/ceremonyclient/node/qclient-2.0.4-darwin-arm64" "$LATEST_QCLIENT_RELEASE"

# Check to see if new release file is in node directory
  # Confirm sizes of sigs are correct
# Update daemons
  # If node, update daemon with new exec start
  # If cluster, update start-cluster file
# Start cluster, supply log file/means of seeing if ok, after 30s print log and exit

CHECK_FILESIZES_func() {
    local FILES_TO_CHECK="$1"

    for FILE in $FILES_TO_CHECK; do
        if [[ "$FILE" =~ ".dgst" ]]; then
            # Check that the .dgst and .sg files are above 100 bytes
            if [[ -n $(find "$FILE" -prune -size +100c) ]]; then
                chmod +x "$FILE"
            else
                echo "Error: file '$FILE' has size of '$(du -h "$FILE")'."
                echo "Check manually to make sure this file downloaded correctly before using it."
            fi
        else
            # Check that the main node/qclient binary ar above 180MB
            if [[ -n $(find "$FILE" -prune -size +180000000c) ]]; then
                chmod +x "$FILE"
            else
                echo "Error: file '$FILE' has size of '$(du -h "$FILE")'."
                echo "Check manually to make sure this file downloaded correctly before using it."
            fi
        fi
    done
}

CONFIRM_NEW_BINARIES_func() {
    NEW_LATEST_NODE_FILE_INSTALLED_PATH=$(./ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
    NEW_LATEST_NODE_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_NODE_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)
    NEW_LATEST_QCLIENT_FILE_INSTALLED_PATH=$(./ceremonyclient_env.sh -latest-version 'qclient-installed-files-quiet')
    NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_QCLIENT_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)

    NEW_LATEST_NODE_FILES=$(find "$CEREMONYCLIENT_NODE_DIR" -type f -name "$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME*")
    NEW_LATEST_QCLIENT_FILES=$(find "$CEREMONYCLIENT_NODE_DIR" -type f -name "$NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME*")

    if [[ "$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME" == "$LATEST_NODE_RELEASE" ]]; then
        CHECK_FILESIZES_func "$NEW_LATEST_NODE_FILES"
    fi
    if [[ "$NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME" == "$LATEST_QCLIENT_RELEASE" ]]; then
        CHECK_FILESIZES_func "$NEW_LATEST_QCLIENT_FILES"
    fi
}

CONFIRM_NEW_BINARIES_func

# If cluster
  # Find start-cluster file, replace node-2.0.5.1 line
# If standalone node
  # Replace node-2.0.5.1 line in each daemon file
# Reload & restart daemons

UPDATE_DAEMON_FILE_func() {
    if [[ $CLUSTER == 1 ]]; then
        # Update start_cluster script
        sed -i "s/NODE_BINARY\=[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    else
        if [[ "$RELEASE_OS" == "darwin" ]]; then
            # Update launchctl plist file
            sudo sed -i "s/node-[^<]*/$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
        elif [[ "$RELEASE_OS" == "linux" ]]; then
            # Update systemctl service file
            sed -i "/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH" /lib/systemd/system/ceremonyclient.service
        fi
    fi
}





while getopts "xhc" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func;;
        c) CLUSTER=1;;
        *) USAGE_func;;
    esac
done
shift $((OPTIND -1))

exit 0

UPDATE_DAEMON_FILE_LINUX_func() {
    systemctl stop ceremonyclient
    sleep 2

    latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_LINE"$)
    chmod +x $latest_node_file
    sed -i "/^ExecStart\=.*/c ExecStart\=/root/ceremonyclient/node/$latest_node_file" /lib/systemd/system/ceremonyclient.service

    latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_LINE"$)
    echo ""
    echo "Latest qclient file: $latest_qclient_file"
    chmod +x $latest_qclient_file

    systemctl daemon-reload
    sleep 2
    systemctl restart ceremonyclient
    echo "ceremonyclient daemon updated and reloaded. Waiting 60s before printing a status read from the ceremonyclient daemon."
    sleep 60
    systemctl status ceremonyclient
}

UPDATE_DAEMON_FILE_MACOS_func() {
    sudo launchctl disable system/local.ceremonyclient
    sleep 2
    sudo launchctl bootout system /Library/LaunchDaemons/local.ceremonyclient.plist
    sleep 2

    latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_LINE"$)
    echo "Latest node file: $latest_node_file"
    chmod +x $latest_node_file
    sudo sed -i 's/node-[^<]*/node-2.0.4.3-darwin-arm64/' /Library/LaunchDaemons/local.ceremonyclient.plist

    latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_LINE"$)
    echo ""
    echo "Latest qclient file: $latest_qclient_file"
    chmod +x $latest_qclient_file

    sudo launchctl enable system/local.ceremonyclient
    sleep 2
    sudo launchctl bootstrap system /Library/LaunchDaemons/local.ceremonyclient.plist
    sleep 2
    launchctl kickstart -kp system/local.ceremonyclient
    echo "ceremonyclient updated and restarted. Waiting 60s before printing a status read from the ceremonyclient daemon."
    sleep 60
    tail -F /Users/robbie/ceremonyclient.log
}



FETCH_FILES_func

if [[ "$RELEASE_OS" = "linux" ]]; then
    UPDATE_DAEMON_FILE_LINUX_func
elif [[ "$RELEASE_OS" = "darwin" ]]; then
    UPDATE_DAEMON_FILE_MACOS_func
fi

echo ""
exit 0