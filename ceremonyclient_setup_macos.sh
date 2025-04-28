#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Sets up a Quilibrium node on this machine."
    echo ""
    echo "USAGE: bash ceremonyclient_setup.sh [-h] [-x] [-q] [-d directory] [-c] [-C core index start] [-D data worker count]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q    Quiet mode."
    echo "       -d    Directory to install node to."
    echo "             By default, this will be gotten from the ceremonyclient_env.sh tool at the beginning of this script."
    echo "       -c    This node is being set up as part of a cluster."
    echo "             (By default this is set to null, meaning this node is run as a standalone node.)"
    echo "       -C    Cluster core index start."
    echo "       -D    Cluster data worker count."
    echo ""
    exit 0
}

# Initialise a .localenv file
# Install dependancies
    # If macOS, install homebrew, then git gmp rsync rclone
    # If Linux, install git make build-essential libgmp-dev rsync rclone wget curl sudo
    # Install Go, Rust, gRPC
    # Set up bashrc/zshrc with Go and Rust
# Download node binary, make it executable
# Download qclient binary, make it executable
# Build the service file, load it up
    # If part of cluster, build service using start_cluster
    # If macOS, launchctl with plutil test and log rotation
    # If Linux, systemctl
# Let run for 3 mins, print output of logs
# Config tips & suggestions instructions
# Config gRPC instructions
# If cluster, config cluster instructions
# Instructions on setting up backups

# Check the .localenv file; if it doesn't exist, initialise one
CHECK_LOCALENV_func() {
    if ./tools/ceremonyclient_check_localenv.sh -q; then
        :
    else
        bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -env-init
    fi
}

# Install dependancies
    # If macOS, install homebrew, then git gmp rsync rclone
    # If Linux, install git make build-essential libgmp-dev rsync rclone wget curl sudo
    # Install Go, Rust, gRPC
    # Set up bashrc/zshrc with Go and Rust

INSTALL_DEPENDANCIES_func() {
    if [[ "$RELEASE_OS" == 'darwin' ]]; then
        # Install brew and brew packages
        if [[ $(brew --version) ]]; then
            :
        else
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"  
            if [[ $SKIP_TERMINAL_PROFILE == 0 ]]; then
                # Get homebrew commands working
                tee -a ~/.zshrc > /dev/null <<EOF

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"



EOF
                . ~/.zshrc
            else
                :
            fi
        fi
        for MAC_BREW_DEPENDANCY in $MAC_BREW_DEPENDANCIES; do
            if brew list -1 "$MAC_BREW_DEPENDANCY"; then
                :
            else
                brew install "$MAC_BREW_DEPENDANCY"
            fi
        done
    elif [[ "$RELEASE_OS" == 'linux' ]]; then
        apt install "$LINUX_APT_DEPENDANCIES"
    fi
}

INSTALL_GO_RUST_func() {
    # Install Go
    curl -s -S -L "$GOLANG_URL" -o go.tar.gz
    tar -f go.tar.gz -xvz
    if [[ -d /usr/local/go ]]; then
        sudo rm -r /usr/local/go
    fi
    sudo mv -f go /usr/local/
    rm go.tar.gz
    if [[ $SKIP_TERMINAL_PROFILE == 0 ]]; then
        # Alter terminal profile for Go
        tee -a $TERMINAL_PROFILE_FILE > /dev/null <<EOF

# Golang
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export GOPROXY=https://goproxy.cn,direct
export PATH=$PATH:/usr/local/go/bin



EOF
        . $TERMINAL_PROFILE_FILE
    else
        :
    fi

    # Install Rust
    if [[ $(rustc --version) ]]; then
        :
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        if [[ $SKIP_TERMINAL_PROFILE == 0 ]]; then
            # Alter terminal profile for Rust
            tee -a $TERMINAL_PROFILE_FILE > /dev/null <<EOF

# Rust
. "$HOME/.cargo/env"



EOF
        . $TERMINAL_PROFILE_FILE
    else
        :
    fi
        cargo install uniffi-bindgen-go --git https://github.com/NordSecurity/uniffi-bindgen-go --tag v0.2.2+v0.25.0
    fi
}

INSTALL_DEPENDANCIES_ALTER_TERMINAL_PROFILES_func() {
    MAC_BREW_DEPENDANCIES="git gmp rsync rclone"
    LINUX_APT_DEPENDANCIES="git make build-essential libgmp-dev rsync rclone wget curl sudo"
    GOLANG_URL="https://go.dev/dl/go1.22.12.$RELEASE_OS-$RELEASE_ARCH.tar.gz"

    INSTALL_DEPENDANCIES_func
    INSTALL_GO_RUST_func

    return
}

# Download node binary, make it executable
# Download qclient binary, make it executable

# Download and make executable the node/qclient binaries
DOWNLOAD_INSTALL_BINARIES_func() {
    bash $SCRIPT_DIR/tools/ceremonyclient_download.sh -f "$NODE_BINARY"
    bash $SCRIPT_DIR/tools/ceremonyclient_download.sh -f "$QCLIENT_BINARY"

    return
}

# Build the service file, load it up
    # If part of cluster, build service using start_cluster
    # If macOS, launchctl with plutil test and log rotation
    # If Linux, systemctl

# Function to update the start_cluster script
UPDATE_CLUSTER_FILE_func() {
    if [[ $CLUSTER == 1 ]]; then
        sed -i'.sed-bak' "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
    fi

    return 0
}

CONFIGURE_LOG_ROTATION_func() {
    if [[ "$RELEASE_OS" == "darwin" ]]; then
        # logrotate
        if brew list -1 logrotate; then
            :
        else
            brew install logrotate
        fi
        LOGROTATE_CONF_FILE=/opt/homebrew/etc/logrotate.d/$PLIST_LABEL.conf
        tee $LOGROTATE_CONF_FILE > /dev/null <<EOF
$CEREMONYCLIENT_LOGFILE {
    copytruncate
    rotate 10
    size 500M
    missingok
    notifempty
    compress
    compressoptions '-9'
}
EOF
        chown $USER:admin /opt/homebrew/etc/logrotate.d/$PLIST_LABEL.conf
        chmod 644 /opt/homebrew/etc/logrotate.d/$PLIST_LABEL.conf

        LOGROTATE_PLIST_FILE=/Library/LaunchDaemons/$PLIST_LABEL-logrotate.plist
        sudo tee $LOGROTATE_PLIST_FILE > /dev/null <<EOF
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL-logrotate</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/sbin/logrotate</string>
        <string>-f</string>
        <string>$LOGROTATE_CONF_FILE</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>
    
    <key>WorkingDirectory</key>
    <string>/opt/homebrew/sbin</string>
    
    <key>UserName</key>
    <string>$USER</string>

    <key>RunAtLoad</key>
    <true/>

    <key>ExitTimeOut</key>
    <integer>30</integer>

    <key>StandardErrorPath</key>
    <string>$CEREMONYCLIENT_LOGROTATE_LOGFILE</string>

    <key>StandardOutPath</key>
    <string>$CEREMONYCLIENT_LOGROTATE_LOGFILE</string>
</dict>
</plist>
EOF
        brew services restart logrotate
        # newsyslog - don't use
#        sudo tee /etc/newsyslog.d/$PLIST_LABEL.conf > /dev/null <<EOF
## logfilename [owner:group] mode count size when flags [/pid_file] [sig_num]
#$CEREMONYCLIENT_LOGFILE robbie:staff 777 3 10240 * JGB
#EOF
    elif [[ "$RELEASE_OS" == "linux" ]]; then
        :
    fi

    return
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

    CONFIGURE_LOG_ROTATION_func

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

CONFIG_CHANGES_func() {
    # Set maxFrames (frame truncation) to 1001 frames, to save on disk space
    sudo sed -i'.sed-bak' -E 's|maxFrames: .*|maxFrames: 1001|' "$CEREMONYCLIENT_CONFIG_FILE"
    # Set store path explicitly
    sudo sed -i'.sed-bak' -E 's|path: .*|path: $CEREMONYCLIENT_CONFIG_DIR/store|' "$CEREMONYCLIENT_CONFIG_FILE"
    # Set logfile
    #sudo sed -i'.sed-bak' -E "s|logFile: .*|logFile: \"$CEREMONYCLIENT_LOGFILE\"|" "$CEREMONYCLIENT_CONFIG_FILE"
    # Enable gRPC
    bash $SCRIPT_DIR/ceremonyclient_grpc.sh -q -g
    bash $SCRIPT_DIR/ceremonyclient_grpc.sh -q -l
    bash $SCRIPT_DIR/ceremonyclient_grpc.sh -q -p

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
        sleep 60

        sudo launchctl stop system/local.ceremonyclient
        CONFIG_CHANGES_func

        # Use kickstart with the -k flag to kill any currently running ceremonyclient services,
        # and -p flag to print the PID of the service that starts up
        # This ensures only one ceremonyclient service running
        sudo launchctl kickstart -kp system/local.ceremonyclient
        # Let service sit for 10 mins, then print out the logfile
        echo "ceremonyclient daemon created, waiting 5 minutes before printing from the logfile ceremonyclient."
        sleep 300
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

VIEW_LOGS_SCRIPT_ON_DESKTOP_func() {
    tee /Users/$USER/Desktop/ceremonyclient_view_logs.command > /dev/null <<EOF
#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

tail -F $CEREMONYCLIENT_LOGFILE
EOF

    chmod ugo+x /Users/$USER/Desktop/ceremonyclient_view_logs.command
}

FINISHING_TIPS_func() {
    echo ""
    echo "Finishing tips:"
    echo "- gRPC has been setup, and the node config has been altered to make use of 'maxFrames: 1001',"
    echo "  so as to limit the store size. Please let your node run, and when it starts printing,"
    echo "  restart it so these changes can take effect."
    echo "- If in future you have a large store folder with maxFramces set to 1000, try starting the node with the"
    echo "  option '--compact-db' and let it run until it quits."
    echo "- When running the node, use the '--config' flag with the config directory. If you're using the"
    echo "  ceremonyclient_start_cluster.sh script, this is already coded in."
    # Terminal profile tips
    if [[ "$RELEASE_OS" == 'darwin' ]]; then
        echo "- A double-clickable file, ceremonyclient_view_logs.command, has been placed on your desktop to make it easier to view logs."
        echo "- For better readability in your terminal profile, copy the following to your ~/.zshrc file:"
        echo "  # Terminal display preferences"
        echo "  autoload -Uz vcs_info"
        echo "  precmd() { vcs_info }"
        echo "  zstyle ':vcs_info:git:*' formats '%b '"
        echo "  setopt PROMPT_SUBST"
        echo "  PROMPT='%F{green}%n@%m%f %F{green}%*%f %F{blue}%~%f %F{red}${vcs_info_msg_0_}%f$ '"
        echo "  and run the command '. $TERMINAL_PROFILE_FILE'."
    elif [[ "$RELEASE_OS" == 'linux' ]]; then
        echo "- For better readability in your terminal profile, copy the following to your ~/.bashrc file:"
        echo "  # Terminal display preferences"
        echo "  PS1='${debian_chroot:+($debian_chroot)}\[\033[0;32m\]\u@\h\[\033[00m\] \[\033[0;32m\]\D{%H:%M:%S}\[\033[00m\] \[\033[0;34m\]\w\[\033[00m\] $ '"
    fi
    # Cluster tips
    if [[ $CLUSTER == 1 ]]; then
        echo "- Make sure to configure the 'dataWorkersMultiaddrs' section of 'engine' in $CEREMONYCLIENT_CONFIG,"
        echo "  and that this section is the same ON ALL MACHINES in order for this node to function as part of the cluster."
    fi
    echo "- To set up backups, rclone must first be set up, then the backup script can be put into a weekly cron job."
    echo "  Run 'rclone config' to add a new remote destination, and enter your remote details."
    echo "  Then you can run the backup script in tools directory, tools/ceremonyclient_backup.sh, and set it to run weekly via cron."
    echo ""

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

# To indicate to the script that this node is being set up as part of a cluster
CLUSTER=0

# Filled with data by using -C and -D; for setting up node as part of cluster
CLUSTER_CORE_INDEX_START=0
CLUSTER_DATA_WORKER_COUNT=0

# Supply a node directory using the -d flag
DIRECTORY=0

# To skip the alterations to terminal profile
SKIP_TERMINAL_PROFILE=0

while getopts "xhqcd:C:D:p" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        c) CLUSTER=1;;
        d) DIRECTORY="$OPTARG";;
        C) CLUSTER_CORE_INDEX_START="$OPTARG";;
        D) CLUSTER_DATA_WORKER_COUNT="$OPTARG";;
        p) SKIP_TERMINAL_PROFILE=1;;
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

# (macOS only) The logfile that will be used for the ceremonyclient
CEREMONYCLIENT_LOGFILE="$HOME/ceremonyclient.log"
CEREMONYCLIENT_LOGROTATE_LOGFILE="$HOME/ceremonyclient-logrotate.log"

# Ceremonyclient config location
CEREMONYCLIENT_CONFIG_FILE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_config")
CEREMONYCLIENT_CONFIG_DIR=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_config_dir")

# Plist name and file
PLIST_LABEL="local.ceremonyclient"
CEREMONYCLIENT_PLIST_FILE=/Library/LaunchDaemons/$PLIST_LABEL.plist

# Get the latest version numbers of the node and qclient binaries from release
NODE_VERSION=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-quiet')
QCLIENT_VERSION=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-quiet')

# Get the latest version files of the node and qclient binaries from release
NODE_BINARY=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
QCLIENT_BINARY=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-files-quiet')

RELEASE_ARCH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

if [[ "$RELEASE_OS" == 'darwin' ]]; then
    TERMINAL_PROFILE_FILE=~/.zshrc
elif [[ "$RELEASE_OS" == 'linux' ]]; then
    TERMINAL_PROFILE_FILE=~/.bashrc
fi

INSTALL_DEPENDANCIES_ALTER_TERMINAL_PROFILES_func

DOWNLOAD_INSTALL_BINARIES_func
ALTER_RELOAD_RESTART_DAEMONS_func

if [[$RELEASE_OS == "darwin" ]]; then
    VIEW_LOGS_SCRIPT_ON_DESKTOP_func
fi

FINISHING_TIPS_func

exit