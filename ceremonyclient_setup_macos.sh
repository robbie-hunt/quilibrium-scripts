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

# Figure out what directory I'm in
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
SCRIPT_ROOT_DIR=$(echo "$SCRIPT_DIR" | awk -F'/' 'BEGIN{OFS=FS} {$NF=""; print}' | sed 's/\/*$//')

# .localenv file location
LOCALENV="$SCRIPT_ROOT_DIR/.localenv"

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
            # Get homebrew commands working
            tee -a ~/.zshrc > /dev/null <<EOF

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"



EOF
            . ~/.zshrc
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
    if [[ "$RELEASE_OS" == 'darwin' ]]; then
        TERMINAL_PROFILE_FILE=~/.zshrc
    elif [[ "$RELEASE_OS" == 'linux' ]]; then
        TERMINAL_PROFILE_FILE=~/.bashrc
    fi

    # Install Go
    curl -s -S -L "$GOLANG_URL" -o go.tar.gz
    tar -f go.tar.gz -xvz
    sudo mv -f go /usr/local/go
    rm go.tar.gz
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

    # Install Rust
    if [[ $(rustc --version) ]]; then
        :
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        # Alter terminal profile for Rust
        tee -a $TERMINAL_PROFILE_FILE > /dev/null <<EOF

# Rust
. "$HOME/.cargo/env"



EOF
        . $TERMINAL_PROFILE_FILE
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
        sed -i "s/NODE_BINARY\=[^<]*/NODE_BINARY\=$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME/" ceremonyclient_start_cluster.sh
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

CONFIG_CHANGES_func() {
    # Enable gRPC
    bash $SCRIPT_DIR/tools/ceremonyclient_grpc.sh -q -g
    bash $SCRIPT_DIR/tools/ceremonyclient_grpc.sh -q -l
    bash $SCRIPT_DIR/tools/ceremonyclient_grpc.sh -q -p

    # Set maxFrames (frame truncation) to 1001 frames, to save on disk space
    sudo sed -i -E 's|maxFrames: .*|maxFrames: 1001|' "$CEREMONYCLIENT_CONFIG_FILE"

    return
}

FINISHING_TIPS_func() {
    echo ""
    if [[ "$RELEASE_OS" == 'darwin' ]]; then
        echo "For better readability in your terminal profile, copy the following to your ~/.zshrc file:"
        echo "# Terminal display preferences"
        echo "autoload -Uz vcs_info"
        echo "precmd() { vcs_info }"
        echo "zstyle ':vcs_info:git:*' formats '%b '"
        echo "setopt PROMPT_SUBST"
        echo "PROMPT='%F{green}%n@%m%f %F{green}%*%f %F{blue}%~%f %F{red}${vcs_info_msg_0_}%f$ '"
    elif [[ "$RELEASE_OS" == 'linux' ]]; then
        echo "For better readability in your terminal profile, copy the following to your ~/.bashrc file:"
        echo "# Terminal display preferences"
        echo "PS1='${debian_chroot:+($debian_chroot)}\[\033[0;32m\]\u@\h\[\033[00m\] \[\033[0;32m\]\D{%H:%M:%S}\[\033[00m\] \[\033[0;34m\]\w\[\033[00m\] $ '"
    fi
    if [[ $CLUSTER == 1 ]]; then
        echo "Make sure to configure the 'dataWorkersMultiaddrs' section of 'engine' in $CEREMONYCLIENT_CONFIG,"
        echo "and that this section is the same ON ALL MACHINES in order for this node to function as part of the cluster."
    fi
    echo "To set up backups, "
    echo ""

    return
}

# Instructions on setting up backups

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

# To indicate to the script that this node is being set up as part of a cluster
CLUSTER=0

# Filled with data by using -C and -D; for setting up node as part of cluster
CLUSTER_CORE_INDEX_START=0
CLUSTER_DATA_WORKER_COUNT=0

# Supply a node directory using the -d flag
DIRECTORY=0

while getopts "xhqcC:D:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        c) CLUSTER=1;;
        d) DIRECTORY="$OPTARG";;
        C) CLUSTER_CORE_INDEX_START="$OPTARG";;
        D) CLUSTER_DATA_WORKER_COUNT="$OPTARG";;
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

# Ceremonyclient config file location
CEREMONYCLIENT_CONFIG_FILE=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_config")

# Plist name and file
PLIST_LABEL="local.ceremonyclient"
PLIST_FILE=/Library/LaunchDaemons/$PLIST_LABEL.plist

# Get the latest version numbers of the node and qclient binaries from release
NODE_VERSION=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-quiet')
QCLIENT_VERSION=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-quiet')

# Get the latest version files of the node and qclient binaries from release
NODE_BINARY=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
QCLIENT_BINARY=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -latest-version 'qclient-release-files-quiet')

RELEASE_ARCH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

INSTALL_DEPENDANCIES_ALTER_TERMINAL_PROFILES_func

DOWNLOAD_INSTALL_BINARIES_func
exit
ALTER_RELOAD_RESTART_DAEMONS_func

CONFIG_CHANGES_func

FINISHING_TIPS_func

exit





FETCH_FILES_func() {
    local FILE_PATTERN="$1"
    local TYPE="$(echo $FILE_PATTERN | awk -F'-' '{print $1}')_release_url"
    local URL=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key $TYPE)

    # List files in most recent release
    RELEASE_FILES_AVAILABLE=$(curl -s -S $URL | grep $FILE_PATTERN)

    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        echo "Error: no release files relating to $FILE_PATTERN could be found."
        echo "This could be due to network issues."
        return 1
    fi

    for RELEASE_FILE in $RELEASE_FILES_AVAILABLE; do
        if curl -s -S "https://releases.quilibrium.com/$RELEASE_FILE" > "$CEREMONYCLIENT_NODE_DIR/$RELEASE_FILE"; then
            echo "Downloaded and installed file: $RELEASE_FILE."
        fi
    done

    return
}



### NODE BINARY DOWNLOAD

# Set up environment variables (redundant but solves the command go not found error)
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

echo "Downloading node binaries..."
mkdir -p ~/ceremonyclient/node
cd ~/ceremonyclient/node

# List files in most recent release
NODE_RELEASE_FILES=$(curl -s -S https://releases.quilibrium.com/release | grep $RELEASE_LINE)
if [[ -z "$NODE_RELEASE_FILES" ]]; then
    echo "Error: No node files found for $RELEASE_LINE"
    echo "This could be due to network issues or no releases for your architecture."
    exit 1
fi

# For each file in most recent release, download it
for NODE_FILE in $NODE_RELEASE_FILES; do
    version=$(echo "$NODE_FILE" | cut -d '-' -f 2)
    if curl -s -S "https://releases.quilibrium.com/$NODE_FILE" > "$NODE_FILE"; then
        :
    fi
done

# Make node binary executable
latest_node_file=$(echo "$NODE_RELEASE_FILES" | grep "$RELEASE_LINE"$)
chmod +x $latest_node_file

sleep 3



### QCLIENT BINARY DOWNLOAD

echo "Downloading qclient binaries..."
mkdir -p ~/ceremonyclient/client
cd ~/ceremonyclient/client

# List files in most recent release
qclientfiles=$(curl -s -S https://releases.quilibrium.com/qclient-release | grep $RELEASE_LINE)
if [[ -z "$qclientfiles" ]]; then
    echo "Error: No qclient files found for $RELEASE_LINE"
    echo "This could be due to network issues or no releases for your architecture."
    exit 1
fi

# For each file in most recent release, download it
for qclientfile in $qclientfiles; do
    version=$(echo "$qclientfile" | cut -d '-' -f 2)
    if curl -s -S "https://releases.quilibrium.com/$qclientfile" > "$qclientfile"; then
        :
    fi
done

# Make qclient binary executable
latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_LINE"$)
chmod +x $latest_qclient_file

echo ""
sleep 3



### BUILDING CEREMONYCLIENT SERVICE

echo "Building ceremonyclient service..."

# Use the home directory in the path
NODE_PATH=$HOME/ceremonyclient/node
NODE_BINARY_PATH=$NODE_PATH/$NODE_BINARY

# Set GOMAXPROCS
# LINUX - Calculate GOMAXPROCS based on the number of threads
#GOMAXPROCS=$(nproc)
# MAC - Calculate GOMAXPROCS based on the number of threads
GOMAXPROCS=$(sysctl -n hw.logicalcpu)

# Setup log file
echo "Creating log file..."   
rm -rf $CEREMONYCLIENT_LOGFILE
touch $CEREMONYCLIENT_LOGFILE   
chmod 644 $CEREMONYCLIENT_LOGFILE

# Create service file
echo "Building service file..."
tee $PLIST_FILE > /dev/null <<EOF
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_BINARY_PATH</string>
    </array>
    <key>UserName</key>
    <string>$USER</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GOMAXPROCS</key>
        <string>$GOMAXPROCS</string>
    </dict>
    <key>ExitTimeOut</key>
    <integer>30</integer>
    <key>WorkingDirectory</key>
    <string>$NODE_PATH</string>
    <key>StandardErrorPath</key>
    <string>$CEREMONYCLIENT_LOGFILE</string>
    <key>StandardOutPath</key>
    <string>$CEREMONYCLIENT_LOGFILE</string>
</dict>
</plist>
EOF

# Test service file
echo "Checking service file..."
PLUTIL_TEST=$(plutil -lint $PLIST_FILE)
if [[ $PLUTIL_TEST == "$PLIST_FILE: OK" ]]; then
    :
fi

# Configure log rotation
echo "Configuring log rotation for ceremonyclient logs. This requires sudo, so please provide password if asked."
sudo tee /etc/newsyslog.d/$PLIST_LABEL.conf > /dev/null <<EOF
# logfilename [owner:group] mode count size when flags [/pid_file] [sig_num]
$CEREMONYCLIENT_LOGFILE robbie:staff 644 3 1024 * JG
EOF

# Start up service
echo "Starting the ceremonyclient service..."
sudo launchctl enable system/$PLIST_LABEL
sleep 3
sudo launchctl bootstrap system $PLIST_FILE
sleep 3
launchctl kickstart -kp system/$PLIST_LABEL
sleep 3



echo ""
echo "Node is now set up and running. Leave it to run for about 20 minutes before stopping it."
echo "Node file:  $NODE_BINARY_PATH"
echo "Log file:   $CEREMONYCLIENT_LOGFILE"
echo "Plist file: $PLIST_FILE"
echo "Use \`tail -F $CEREMONYCLIENT_LOGFILE\` to view in real-time the output of the node."
echo "The logfile is rotated when it reaches 1GB in filesize, and 2 archives are kept. This will result in a total disk usage of 3GB by the logfile and archives."
echo "If you want to add gRPC, you should wait about 20 minutes for the node to sync up, then run the gRPC script."

exit