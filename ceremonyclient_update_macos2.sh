#!/bin/bash

echo ""

RELEASE_ARCH=$(./ceremonyclient_env.sh -arch)
RELEASE_OS=$(./ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

LATEST_VERSIONS=$(./ceremonyclient_env.sh -latest-version 'files-quiet')
LATEST_VERSION_NODE_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '1q;d')
LATEST_VERSION_NODE_RELEASE=$(echo "$LATEST_VERSIONS" | sed '2q;d')
LATEST_VERSION_QCLIENT_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '3q;d')
LATEST_VERSION_QCLIENT_RELEASE=$(echo "$LATEST_VERSIONS" | sed '4q;d')

echo "LATEST_VERSION_NODE_INSTALLED: $LATEST_VERSION_NODE_INSTALLED"
echo "LATEST_VERSION_NODE_RELEASE: $LATEST_VERSION_NODE_RELEASE"
echo "LATEST_VERSION_QCLIENT_INSTALLED: $LATEST_VERSION_QCLIENT_INSTALLED"
echo "LATEST_VERSION_QCLIENT_RELEASE: $LATEST_VERSION_QCLIENT_RELEASE"

## Function to fetch update files
FETCH_FILES_func() {
    local FILE_PATTERN="$1"

    # List files in most recent release
    RELEASE_FILES_AVAILABLE=$(curl -s -S ./ceremonyclient_env.sh -key '`echo $FILE_PATTERN | awk -F'-' '{print $1}'`_release_url' | grep $FILE_PATTERN)
    echo "RELEASE_FILES_AVAILABLE: $RELEASE_FILES_AVAILABLE"
    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        echo "Error: no release files relating to $FILE_PATTERN could be found."
        echo "This could be due to network issues."
        exit 1
    fi

    # For each file in most recent release, download it
    #for nodefile in $nodefiles; do
    #    version=$(echo "$nodefile" | cut -d '-' -f 2)
    #    if curl -s -S "https://releases.quilibrium.com/$nodefile" > "$nodefile"; then
    #        echo "Downloaded and installed $nodefile"
    #    fi
    #    new_release=true
    #done
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

COMPARE_VERSIONS_func "$LATEST_VERSION_NODE_INSTALLED" "$LATEST_VERSION_NODE_RELEASE"
COMPARE_VERSIONS_func "$LATEST_VERSION_QCLIENT_INSTALLED" "$LATEST_VERSION_QCLIENT_RELEASE"

exit 0

UPDATE_DAEMON_FILE_LINUX_func() {
    systemctl stop ceremonyclient
    sleep 2

    latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_LINE"$)
    echo "Latest node file: $latest_node_file"
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