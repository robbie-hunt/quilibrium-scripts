#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed



### MANUALLY SET NODE/QCLIENT VERSIONS

# Comment out for use of the latest node version
NODE_VERSION=""

# Comment out for use of the latest qclient version
QCLIENT_VERSION=""


echo ""
sleep 2

### DETERMINATIONS & VARIABLES

# Define the home dierctory
HOME=$(eval echo ~$USER)

# Define the logfile
CEREMONYCLIENT_LOGFILE=$HOME/ceremonyclient.log

# Label for plist
PLIST_LABEL="local.ceremonyclient"

# Path for the plist launchctl file
PLIST_FILE=/Library/LaunchDaemons/$PLIST_LABEL.plist

# Determine Go version
GO_VERSION=$(go version | awk '{print $3}')

# Determine node latest version
if [[ -z "$NODE_VERSION" ]]; then
    NODE_VERSION=$(curl -s https://releases.quilibrium.com/release | grep -E "^node-[0-9]+(\.[0-9]+)*" | grep -v "dgst" | sed 's/^node-//' | cut -d '-' -f 1 | head -n 1)
    echo "Automatically determined NODE_VERSION:    $NODE_VERSION"
else
    echo "Using specified NODE_VERSION: $NODE_VERSION"
fi

# Determine qclient latest version
if [[ -z "$QCLIENT_VERSION" ]]; then
    QCLIENT_VERSION=$(curl -s https://releases.quilibrium.com/qclient-release | grep -E "^qclient-[0-9]+(\.[0-9]+)*" | sed 's/^qclient-//' | cut -d '-' -f 1 |  head -n 1)
    echo "Automatically determined QCLIENT_VERSION: $QCLIENT_VERSION"
else
    echo "Using specified QCLIENT_VERSION: $QCLIENT_VERSION"
fi

# Determine the CPU arch and OS, and the appropriate binaries
RELEASE_ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
RELEASE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [[ "$RELEASE_ARCH" = "x86_64" ]]; then
    if [[ "$RELEASE_OS" = "linux" ]]; then
        NODE_BINARY="node-$NODE_VERSION-linux-amd64"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-linux-amd64"
    elif [[ "$RELEASE_OS" = "darwin" ]]; then
        NODE_BINARY="node-$NODE_VERSION-darwin-amd64"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-darwin-amd64"
    else
        echo "Error: couldn't match OS to available OS's for Quil. Run \`uname -s | tr '[:upper:]' '[:lower:]'\` to debug."
        exit 1
    fi
elif [[ "$RELEASE_ARCH" = "aarch64" || "$RELEASE_ARCH" = "arm64" ]]; then
    if [[ "$RELEASE_OS" = "linux" ]]; then
        NODE_BINARY="node-$NODE_VERSION-linux-arm64"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-linux-arm64"
    elif [[ "$RELEASE_OS" = "darwin" ]]; then
        NODE_BINARY="node-$NODE_VERSION-darwin-arm64"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-darwin-arm64"
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



### NODE BINARY DOWNLOAD

# Set up environment variables (redundant but solves the command go not found error)
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

echo "Downloading node binaries..."
mkdir -p ~/ceremonyclient/node
cd ~/ceremonyclient/node

# List files in most recent release
nodefiles=$(curl -s -S https://releases.quilibrium.com/release | grep $RELEASE_OS-$RELEASE_ARCH)
if [[ -z "$nodefiles" ]]; then
    echo "Error: No node files found for $RELEASE_OS-$RELEASE_ARCH"
    echo "This could be due to network issues or no releases for your architecture."
    exit 1
fi

# For each file in most recent release, download it
for nodefile in $nodefiles; do
    version=$(echo "$nodefile" | cut -d '-' -f 2)
    if curl -s -S "https://releases.quilibrium.com/$nodefile" > "$nodefile"; then
        :
    fi
done

# Make node binary executable
latest_node_file=$(echo "$nodefiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
chmod +x $latest_node_file

sleep 3



### QCLIENT BINARY DOWNLOAD

echo "Downloading qclient binaries..."
mkdir -p ~/ceremonyclient/client
cd ~/ceremonyclient/client

# List files in most recent release
qclientfiles=$(curl -s -S https://releases.quilibrium.com/qclient-release | grep $RELEASE_OS-$RELEASE_ARCH)
if [[ -z "$qclientfiles" ]]; then
    echo "Error: No qclient files found for $RELEASE_OS-$RELEASE_ARCH"
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
latest_qclient_file=$(echo "$qclientfiles" | grep "$RELEASE_OS-$RELEASE_ARCH"$)
chmod +x $latest_qclient_file

echo ""
sleep 3



### BUILDING CEREMONYCLIENT SERVICE

echo "Building ceremonyclient service..."

# Use the home directory in the path
NODE_PATH=$HOME/ceremonyclient/node
NODE_BINARY_PATH=$NODE_PATH/$NODE_BINARY

# LINUX - Calculate GOMAXPROCS based on the number of threads
#GOMAXPROCS=$(nproc)
# MAC - Calculate GOMAXPROCS based on the number of threads
GOMAXPROCS=$(sysctl -n hw.logicalcpu)
    
echo "Creating log file..."   
rm -rf $CEREMONYCLIENT_LOGFILE
touch $CEREMONYCLIENT_LOGFILE   
chmod 644 $CEREMONYCLIENT_LOGFILE

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

echo "Checking service file..."
PLUTIL_TEST=$(plutil -lint $PLIST_FILE)
if [[ $PLUTIL_TEST == "$PLIST_FILE: OK" ]]; then
    :
fi

echo "Configuring log rotation for ceremonyclient logs. This requires sudo, so please provide password if asked."
sudo tee /etc/newsyslog.d/$PLIST_LABEL.conf > /dev/null <<EOF
# logfilename [owner:group] mode count size when flags [/pid_file] [sig_num]
$CEREMONYCLIENT_LOGFILE robbie:staff 644 3 1024 * JG
EOF

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