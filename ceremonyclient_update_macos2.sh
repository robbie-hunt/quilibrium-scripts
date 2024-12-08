#!/bin/bash

echo ""

RELEASE_ARCH=$(./ceremonyclient_env.sh -arch)
RELEASE_OS=$(./ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

## Function to fetch update files
FETCH_FILES_func() {
    ## NODE
    # List files in most recent release
    nodefiles=$(curl -s -S https://releases.quilibrium.com/release | grep $RELEASE_LINE)
    if [[ -z "$nodefiles" ]]; then
        echo "Error: No node files found for $RELEASE_LINE"
        echo "This could be due to network issues or no releases for your architecture."
        exit 1
    fi

    new_release=false

    echo "Most recent node release files from https://releases.quilibrium.com/release:"
    echo "$nodefiles"
    cd /root/ceremonyclient/node
    # For each file in most recent release, download it
    for nodefile in $nodefiles; do
        version=$(echo "$nodefile" | cut -d '-' -f 2)
        if curl -s -S "https://releases.quilibrium.com/$nodefile" > "$nodefile"; then
            echo "Downloaded and installed $nodefile"
        fi
        new_release=true
    done

    ## QCLIENT
    # List files in most recent release
    qclientfiles=$(curl -s -S https://releases.quilibrium.com/qclient-release | grep $RELEASE_LINE)

    new_release=false

    echo "Most recent Qclient release files from https://releases.quilibrium.com/release:"
    echo "$qclientfiles"
    cd /root/ceremonyclient/qclient
    # For each file in most recent release, download it
    for qclientfile in $qclientfiles; do
        version=$(echo "$qclientfile" | cut -d '-' -f 2)
        if curl -s -S "https://releases.quilibrium.com/$qclientfile" > "$qclientfile"; then
            echo "Downloaded and installed $qclientfile"
        fi
        new_release=true
    done
}

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