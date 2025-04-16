#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Tool to alter the daemon files of nodes on Debian (Linux) and macOS."
    echo ""
    echo "USAGE: bash ceremonyclient_alter_daemons.sh [-h] [-x] [-q]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q    Quiet mode."
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

# Function to update the start_cluster script
UPDATE_CLUSTER_FILE_func() {
    if [[ $CLUSTER == 1 ]]; then
        sed -i'.sed-bak' "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    fi

    return 0
}

# Function to fill the correct 'Program' and 'ProgramArgs' sections of the macOS plist file,
# including a GOMAXPROCS environment variable, depending on whether this node is being set up as part of a cluster or not
PLIST_ARGS_func() {
    if [[ $CLUSTER == 1 ]]; then
        PLIST_ARGS="<key>Program</key>
    <string>$SCRIPT_ROOT_DIR/ceremonyclient_start_cluster.sh</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_ROOT_DIR/ceremonyclient_start_cluster.sh</string>
        <string>--core-index-start</string>
        <string>$CLUSTER_CORE_INDEX_START</string>
        <string>--data-worker-count</string>
        <string>$CLUSTER_DATA_WORKER_COUNT</string>
    </array>
    
    <key>WorkingDirectory</key>
    <string>$SCRIPT_ROOT_DIR</string>"
    else
        PLIST_ARGS="<key>Program</key>
    <string>$CEREMONYCLIENT_NODE_DIR/$NODE_BINARY</string>
    <key>ProgramArguments</key>
    <string>$CEREMONYCLIENT_NODE_DIR/$NODE_BINARY</string>
    
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

    tee $PLIST_FILE > /dev/null <<EOF
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
    PLUTIL_TEST=$(plutil -lint $PLIST_FILE)
    if [[ $PLUTIL_TEST == "$PLIST_FILE: OK" ]]; then
        :
    else
        echo "Error: plutil test on $PLIST_FILE file failed. Results below:"
        echo "$PLUTIL_TEST"
        return 1
    fi

    # Configure log rotation
    sudo tee /etc/newsyslog.d/$PLIST_LABEL.conf > /dev/null <<EOF
# logfilename [owner:group] mode count size when flags [/pid_file] [sig_num]
$CEREMONYCLIENT_LOGFILE robbie:staff 644 3 1024 * JG
EOF

    return
}

SYSTEMCTL_SERVICE_FILE_ARGS_func() {
    # If cluster, update the ceremonyclient_start_cluster.sh file with the right details
    # so it can be used in the systemctl service file
    if [[ $CLUSTER == 1 ]]; then
        SYSTEMCTL_SERVICE_FILE_ARGS="ExecStart=$SCRIPT_ROOT_DIR/ceremonyclient_start_cluster.sh --core-index-start $CLUSTER_CORE_INDEX_START --data-worker-count $CLUSTER_DATA_WORKER_COUNT"
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
        BUILD_MAC_LAUNCHCTL_PLIST_FILE_func

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
        echo "ceremonyclient daemon updated and restarted. Waiting 2 minutes before printing from the logfile ceremonyclient."
        sleep 120
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

while getopts "xhqcC:D:d" opt; do
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

exit