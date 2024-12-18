#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

### DETERMINATIONS & VARIABLES

HOME=$(eval echo ~$USER)
CEREMONYCLIENT_NODE_DIR=$(./tools/ceremonyclient_env.sh -key "ceremonyclient_node_dir")
CEREMONYCLIENT_LOGFILE="$HOME/ceremonyclient.log"

PLIST_LABEL="local.ceremonyclient"
PLIST_FILE=/Library/LaunchDaemons/$PLIST_LABEL.plist

GO_VERSION=$(go version | awk '{print $3}')
NODE_VERSION=$(./tools/ceremonyclient_env.sh -latest-version 'node-release-quiet')
QCLIENT_VERSION=$(./tools/ceremonyclient_env.sh -latest-version 'qclient-release-quiet')

NODE_BINARY=$(./tools/ceremonyclient_env.sh -latest-version 'node-release-files-quiet')
QCLIENT_BINARY=$(./tools/ceremonyclient_env.sh -latest-version 'qclient-release-files-quiet')

RELEASE_LINE=$(./tools/ceremonyclient_env.sh -release-line)

echo ""
sleep 3



FETCH_FILES_func() {
    local FILE_PATTERN="$1"
    local TYPE="$(echo $FILE_PATTERN | awk -F'-' '{print $1}')_release_url"
    local URL=$(./tools/ceremonyclient_env.sh -key $TYPE)

    # List files in most recent release
    RELEASE_FILES_AVAILABLE=$(curl -s -S $URL | grep $FILE_PATTERN)

    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        echo "Error: no release files relating to $FILE_PATTERN could be found."
        echo "This could be due to network issues."
        exit 1
    fi

    for RELEASE_FILE in $RELEASE_FILES_AVAILABLE; do
        if curl -s -S "https://releases.quilibrium.com/$RELEASE_FILE" > "$CEREMONYCLIENT_NODE_DIR/$RELEASE_FILE"; then
            echo "Downloaded and installed file: $RELEASE_FILE."
        fi
    done
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

exit 0