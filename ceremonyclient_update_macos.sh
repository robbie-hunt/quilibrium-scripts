#!/bin/bash

echo ""
cd /root/ceremonyclient/node



# Determine the CPU arch and OS, and the appropriate binaries
RELEASE_ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
RELEASE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ "$RELEASE_ARCH" = "x86_64" ]]; then
    if [[ "$RELEASE_OS" = "linux" ]]; then
        :
    elif [[ "$RELEASE_OS" = "darwin" ]]; then
        :
    else
        echo "Error: couldn't match OS to available OS's for Quil. Run \`uname -s | tr '[:upper:]' '[:lower:]'\` to debug."
        exit 1
    fi
elif [[ "$RELEASE_ARCH" = "aarch64" || "$RELEASE_ARCH" = "arm64" ]]; then
    RELEASE_ARCH="arm64"
    if [[ "$RELEASE_OS" = "linux" ]]; then
        :
    elif [[ "$RELEASE_OS" = "darwin" ]]; then
        :
    else
        echo "Error: couldn't match OS to available OS's for Quil. Run \`uname -s | tr '[:upper:]' '[:lower:]'\` to debug."
        exit 1
    fi
else
    echo "Error: couldn't determine CPU architecture. Run \`uname -m | tr '[:upper:]' '[:lower:]'\` to debug."
    exit 1
fi

echo "Determined environment: $RELEASE_ARCH, $RELEASE_OS"

echo ""
sleep 3



## Function to fetch update files
fetch() {
    ## NODE
    # List files in most recent release
    nodefiles=$(curl -s -S https://releases.quilibrium.com/release | grep $RELEASE_OS-$RELEASE_ARCH)
    if [[ -z "$nodefiles" ]]; then
        echo "Error: No node files found for $RELEASE_OS-$RELEASE_ARCH"
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
    qclientfiles=$(curl -s -S https://releases.quilibrium.com/qclient-release | grep $RELEASE_OS-$RELEASE_ARCH)

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

update_daemon_file_linux() {
    systemctl stop ceremonyclient
    sleep 2

    latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
    echo "Latest node file: $latest_node_file"
    chmod +x $latest_node_file
    sed -i "/^ExecStart\=.*/c ExecStart\=/root/ceremonyclient/node/$latest_node_file" /lib/systemd/system/ceremonyclient.service

    latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
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

update_daemon_file_macos() {
    sudo launchctl disable system/local.ceremonyclient
    sleep 2
    sudo launchctl bootout system /Library/LaunchDaemons/local.ceremonyclient.plist
    sleep 2

    latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
    echo "Latest node file: $latest_node_file"
    chmod +x $latest_node_file
    sed -i "/^ExecStart\=.*/c ExecStart\=/root/ceremonyclient/node/$latest_node_file" /lib/systemd/system/ceremonyclient.service

    latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
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
    tail -F /
}



fetch

if [[ "$RELEASE_OS" = "linux" ]]; then
    update_daemon_file_linux
elif [[ "$RELEASE_OS" = "darwin" ]]; then
    update_daemon_file_macos
fi

echo ""
exit 0