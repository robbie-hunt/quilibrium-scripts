# #!/bin/bash

# Set shell options
set -eou pipefail
set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Updates the Quilibrium node binaries (including qclient) to latest versions, and restarts node daemons."
    echo ""
    echo "USAGE: bash ceremonyclient_update.sh [-h] [-x] [-c]"
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

# Check the .localenv file; if it doesn't exist, initialise one
CHECK_LOCALENV_func() {
    if ./tools/ceremonyclient_check_localenv.sh -q; then
        :
    else
        bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -env-init
    fi
}

# Compare the currently installed binary with the latest available binary from release
COMPARE_VERSIONS_func() {
    local FILE_INSTALLED=$(echo $1 | awk -F'/' '{print $NF}' | xargs)
    local FILE_INSTALLED_PATH="$1"
    local FILE_RELEASE="$2"

    if [[ "$FILE_INSTALLED" == "$FILE_RELEASE" ]]; then
        echo "$FILE_INSTALLED file installed is the latest version, no need to update."
    else
        UPDATE_AVAILABLE=1
        echo "Update required for $FILE_INSTALLED."
        bash $SCRIPT_DIR/tools/ceremonyclient_download.sh -f "$FILE_RELEASE"
    fi
    return
}

# Update either the start_cluster script or the actual service file with the new node binary, depending on whether -c was used
UPDATE_SERVICE_FILE_func() {
    # If cluster, update start_cluster script
    if [[ $CLUSTER == 1 ]]; then
        sed -i'.sed-bak' "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    # If not cluster, then
    else
        # If macOS, update launchctl plist file
        if [[ "$RELEASE_OS" == "darwin" ]]; then
            sudo sed -i'.sed-bak' "s/node-[^<]*/node-$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
        # If Linux, update systemctl service file
        elif [[ "$RELEASE_OS" == "linux" ]]; then
            sed -i'.sed-bak' "s/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH/" /lib/systemd/system/ceremonyclient.service
        fi
    fi
    return
}

UPDATE_CLUSTER_FILE_func() {
    # Update start_cluster script
    if [[ $CLUSTER == 1 ]]; then
        sed -i'.sed-bak' "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    fi

    return 0
}

UPDATE_LAUNCHCTL_PLIST_FILE_func() {
    # Update launchctl plist file
    if [[ $CLUSTER == 1 ]]; then
        sudo sed -i'.sed-bak' "s/node-[^<]*/node-$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" /Library/LaunchDaemons/local.ceremonyclient.plist
    fi

    return 0
}

UPDATE_LAUNCHCTL_PLIST_FILE_func() {
    # Update systemctl service file
    if [[ $CLUSTER == 1 ]]; then
        sed -i'.sed-bak' "s/^ExecStart\=.*/c ExecStart\=$NEW_LATEST_NODE_FILE_INSTALLED_PATH/" /lib/systemd/system/ceremonyclient.service
    fi

    return 0
}

# Function to fill the correct 'Program' and 'ProgramArgs' sections of the macOS plist file,
# including a GOMAXPROCS environment variable, depending on whether this node is being set up as part of a cluster or not
PLIST_ARGS_func() {
    if [[ $CLUSTER == 1 ]]; then
        PLIST_ARGS="<key>Program</key>
    <string>$SCRIPT_DIR/ceremonyclient_start_cluster.sh</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/ceremonyclient_start_cluster.sh</string>
        <string>--core-index-start</string>
        <string>$CLUSTER_CORE_INDEX_START</string>
        <string>--data-worker-count</string>
        <string>$CLUSTER_DATA_WORKER_COUNT</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$SCRIPT_PARENT_DIR</string>"
    else
        PLIST_ARGS="<key>Program</key>
    <string>$CEREMONYCLIENT_NODE_DIR/$NODE_BINARY</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CEREMONYCLIENT_NODE_DIR/$NODE_BINARY</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$CEREMONYCLIENT_NODE_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>GOMAXPROCS</key>
        <string>$GOMAXPROCS</string>
    </dict>"
    fi

    return
}

BUILD_MAC_LAUNCHCTL_PLIST_FILE_func() {
    # Calculate GOMAXPROCS based on the number of threads
    GOMAXPROCS=$(sysctl -n hw.logicalcpu)

    # If cluster, update the ceremonyclient_start_cluster.sh file with the right details
    # so it can be used in the plist file
    if [[ $CLUSTER == 1 ]]; then
        UPDATE_CLUSTER_FILE_func
    fi

    # Setup log file
    rm -rf $CEREMONYCLIENT_LOGFILE
    touch $CEREMONYCLIENT_LOGFILE   
    chmod 644 $CEREMONYCLIENT_LOGFILE

    # Generate the plist file arguments that change depending on whether this is a cluster node or not
    PLIST_ARGS_func

    sudo tee $CEREMONYCLIENT_PLIST_FILE > /dev/null <<EOF
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>

    $PLIST_ARGS
    
    <key>UserName</key>
    <string>$USER</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    
    <key>EnableTransactions</key>
    <false/>

    <key>ExitTimeOut</key>
    <integer>30</integer>

    <key>StandardErrorPath</key>
    <string>$CEREMONYCLIENT_LOGFILE</string>

    <key>StandardOutPath</key>
    <string>$CEREMONYCLIENT_LOGFILE</string>
</dict>
</plist>
EOF

    # Test service file
    PLUTIL_TEST=$(plutil -lint $CEREMONYCLIENT_PLIST_FILE)
    if [[ $PLUTIL_TEST == "$CEREMONYCLIENT_PLIST_FILE: OK" ]]; then
        :
    else
        echo "Error: plutil test on $CEREMONYCLIENT_PLIST_FILE file failed. Results below:"
        echo "$PLUTIL_TEST"
        return 1
    fi

    return
}

SYSTEMCTL_SERVICE_FILE_ARGS_func() {
    # If cluster, update the ceremonyclient_start_cluster.sh file with the right details
    # so it can be used in the systemctl service file
    if [[ $CLUSTER == 1 ]]; then
        SYSTEMCTL_SERVICE_FILE_ARGS="ExecStart=$SCRIPT_DIR/ceremonyclient_start_cluster.sh --core-index-start $CLUSTER_CORE_INDEX_START --data-worker-count $CLUSTER_DATA_WORKER_COUNT"
    else
        SYSTEMCTL_SERVICE_FILE_ARGS="ExecStart=$CEREMONYCLIENT_NODE_DIR/$NODE_BINARY
Environment='GOMAXPROCS=$GOMAXPROCS'"
    fi

    return
}

BUILD_LINUX_SYSTEMCTL_SERVICE_FILE_func() {
    # Calculate GOMAXPROCS based on the number of threads
    GOMAXPROCS=$(nproc)

    if [[ $CLUSTER == 1 ]]; then
        UPDATE_CLUSTER_FILE_func
    fi

    # Generate the systemctl service file arguments that change depending on whether this is a cluster node or not
    SYSTEMCTL_SERVICE_FILE_ARGS_func

    tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=ceremonyclient service

[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$CEREMONYCLIENT_NODE_DIR
$SYSTEMCTL_SERVICE_FILE_ARGS
KillSignal=SIGINT
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF

    return
}

ALTER_RELOAD_RESTART_DAEMONS_func() {
    NEW_LATEST_NODE_FILE_INSTALLED_PATH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
    NEW_LATEST_NODE_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_NODE_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)

    # If macOS, then update launchctl plist file and restart service
    # Using launchctl commands 'bootout' and 'bootstrap' instead of the deprecated 'load' and 'unload' commands
    if [[ "$RELEASE_OS" == "darwin" ]]; then
        # Unload the plist before editing it and starting it up again
        sudo launchctl stop system/local.ceremonyclient
        sleep 2
        sudo launchctl bootout system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2
        BUILD_MAC_LAUNCHCTL_PLIST_FILE_func

        # Enable, load and start service
        sudo launchctl enable system/local.ceremonyclient
        sleep 2
        sudo launchctl bootstrap system /Library/LaunchDaemons/local.ceremonyclient.plist
        sleep 2
        # Use kickstart with the -k flag to kill any currently running ceremonyclient services,
        # and -p flag to print the PID of the service that starts up
        # This ensures only one ceremonyclient service running
        sudo launchctl kickstart -kp system/local.ceremonyclient
        # Let service sit for 10 mins, then print out the logfile
        echo "ceremonyclient daemon created, waiting 10 minutes before printing from the logfile ceremonyclient."
        sleep 600

        tail -200 "$CEREMONYCLIENT_LOGFILE"
        echo "---- End of logs print ----"
        echo ""
    # If Linux, then update systemctl service file and restart service
    elif [[ "$RELEASE_OS" == "linux" ]]; then
        BUILD_LINUX_SYSTEMCTL_SERVICE_FILE_func

        # Enable, load and start service
        systemctl daemon-reload
        sleep 2
        systemctl start ceremonyclient

        # Let service sit for 60s, then print out the logfile
        echo "ceremonyclient service updated and reloaded. Waiting 2 minutes before printing from the logfile ceremonyclient."
        sleep 120
        journalctl --unit=ceremonyclient.service -n 200
        echo "---- End of logs print ----"
        echo ""
    fi

    return
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

# .localenv file location
LOCALENV="$SCRIPT_PARENT_DIR/.localenv"

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

# Set to 1 by using the -c flag; indicates that this node is running as part of a cluster
# This simply means that when it comes to updating daemon/service files, this script will update the
# ceremonyclient_start_cluster.sh script with the new node filename, and not the daemon/service file.
CLUSTER=0

# Filled with data by using -C and -D; for setting up node as part of cluster
CLUSTER_CORE_INDEX_START=0
CLUSTER_DATA_WORKER_COUNT=0

# Supply a node directory using the -d flag
DIRECTORY=0

while getopts "xhqcC:D:d:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        c) CLUSTER=1;;
        C) CLUSTER_CORE_INDEX_START="$OPTARG";;
        D) CLUSTER_DATA_WORKER_COUNT="$OPTARG";;
        d) DIRECTORY="$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

CHECK_LOCALENV_func

# Make sure that if -c is used, -C and -D are also supplied
if [[ "$CLUSTER" == 1 ]]; then
    if [[ "$CLUSTER_CORE_INDEX_START" == 0 || "$CLUSTER_DATA_WORKER_COUNT" == 0 ]]; then
        echo "Error: when using -c to indicate that this node is being set up as part of a cluster,"
        echo "please also use the [-C core index] and [-D number of data workers] flags."
        exit 1
    fi
    :
else
    :
fi

# For the ceremonyclient node directory
# If a directory was supplied via the -d option, use it
# Otherwise, use the directory in the .localenv
if [[ $DIRECTORY == 0 ]]; then
    CEREMONYCLIENT_NODE_DIR=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_node_dir")
else
    CEREMONYCLIENT_NODE_DIR="$DIRECTORY"
fi

# The OS of the machine running this script
RELEASE_OS=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
# The release line ('os-arch') of the machine running this script
RELEASE_LINE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -release-line)

# (macOS only) The logfile that will be used for the ceremonyclient
CEREMONYCLIENT_LOGFILE="$HOME/ceremonyclient.log"
CEREMONYCLIENT_LOGROTATE_LOGFILE="$HOME/ceremonyclient-logrotate.log"

# Get the latest version of the main node and qclient binaries,
# both installed and available in release
LATEST_NODE_INSTALLED=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
LATEST_NODE_RELEASE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
LATEST_QCLIENT_INSTALLED=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-installed-files-quiet')
LATEST_QCLIENT_RELEASE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-files-quiet')

UPDATE_AVAILABLE=0

COMPARE_VERSIONS_func "$LATEST_NODE_INSTALLED" "$LATEST_NODE_RELEASE"
COMPARE_VERSIONS_func "$LATEST_QCLIENT_INSTALLED" "$LATEST_QCLIENT_RELEASE"

if [[ $UPDATE_AVAILABLE == 1 ]]; then
    :
else
    echo "No updates are available."
    exit
fi

ALTER_RELOAD_RESTART_DAEMONS_func

exit