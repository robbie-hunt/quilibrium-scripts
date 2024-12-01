#!/bin/bash

# Comment out for use of the latest node version
#NODE_VERSION=2.0

# Comment out for use of the latest qclient version
#QCLIENT_VERSION=1.4.19.1

# Determine the ExecStart line based on the architecture
ARCH=$(uname -m)
OS=$(uname -s)


### Determine node latest version
# Check if NODE_VERSION is empty
if [ -z "$NODE_VERSION" ]; then
    NODE_VERSION=$(curl -s https://releases.quilibrium.com/release | grep -E "^node-[0-9]+(\.[0-9]+)*" | grep -v "dgst" | sed 's/^node-//' | cut -d '-' -f 1 | head -n 1)
    echo "✅ Automatically determined NODE_VERSION: $NODE_VERSION"
else
    echo "✅ Using specified NODE_VERSION: $NODE_VERSION"
fi

### Determine qclient latest version
# Check if QCLIENT_VERSION is empty
if [ -z "$QCLIENT_VERSION" ]; then
    QCLIENT_VERSION=$(curl -s https://releases.quilibrium.com/qclient-release | grep -E "^qclient-[0-9]+(\.[0-9]+)*" | sed 's/^qclient-//' | cut -d '-' -f 1 |  head -n 1)
    echo "✅ Automatically determined QCLIENT_VERSION: $QCLIENT_VERSION"
else
    echo "✅ Using specified QCLIENT_VERSION: $QCLIENT_VERSION"
fi


### Determine the node binary name based on the architecture and OS
if [ "$ARCH" = "x86_64" ]; then
    if [ "$OS" = "Linux" ]; then
        NODE_BINARY="node-$NODE_VERSION-linux-amd64"
        GO_BINARY="go1.22.4.linux-amd64.tar.gz"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-linux-amd64"
    elif [ "$OS" = "Darwin" ]; then
        NODE_BINARY="node-$NODE_VERSION-darwin-amd64"
        GO_BINARY="go1.22.4.darwin-amd64.tar.gz"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-darwin-amd64"
    fi
elif [ "$ARCH" = "aarch64" ]; then
    if [ "$OS" = "Linux" ]; then
        NODE_BINARY="node-$NODE_VERSION-linux-arm64"
        GO_BINARY="go1.22.4.linux-arm64.tar.gz"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-linux-arm64"
    elif [ "$OS" = "Darwin" ]; then
        NODE_BINARY="node-$NODE_VERSION-darwin-arm64"
        GO_BINARY="go1.22.4.darwin-arm64.tar.gz"
        QCLIENT_BINARY="qclient-$QCLIENT_VERSION-darwin-arm64"
    fi
fi


# Exit on any error
set -e

# Define a function for displaying exit messages
exit_message() {
    echo "❌ Oops! There was an error during the script execution and the process stopped. No worries!"
    echo "You can try to run the script from scratch again."
    echo
    echo "If you still receive an error, you may want to proceed manually, step by step instead of using the auto-installer."
    echo "The step by step installation instructions are here: https://iri.quest/q-node-step-by-step"
}

# Set a trap to call exit_message on any error
trap exit_message ERR


### Download ceremonyclient
echo "⏳ Downloading Ceremonyclient..."
cd ~
if [ -d "ceremonyclient" ]; then
  echo "Directory ceremonyclient already exists, skipping git clone..."
else
  until git clone https://github.com/QuilibriumNetwork/ceremonyclient.git || git clone https://source.quilibrium.com/quilibrium/ceremonyclient.git; do
    echo "Git clone failed, retrying..."
    sleep 2
  done
fi
cd ~/ceremonyclient/
git checkout release

### Set up environment variables (redundant but solves the command go not found error)
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

### Building qClient binary
echo "⏳ Downloading qClient..."
cd ~/ceremonyclient/client

if ! wget https://releases.quilibrium.com/$QCLIENT_BINARY; then
    echo "❌ Error: Failed to download qClient binary."
    echo "Your node will still work, you can install the qclient manually later."
    echo
else
    mv $QCLIENT_BINARY qclient
    chmod +x qclient
    echo "✅ qClient binary downloaded successfully."
    echo
fi

### Get the current user's home directory
HOME=$(eval echo ~$USER)

### Use the home directory in the path
NODE_PATH="$HOME/ceremonyclient/node"
EXEC_START="$NODE_PATH/release_autorun.sh"

### Step 6: Create Ceremonyclient Service
echo "⏳ Creating Ceremonyclient Service"

# Calculate GOMAXPROCS based on the system's RAM
calculate_gomaxprocs() {
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local cpu_cores=$(nproc)
    local gomaxprocs=$((ram_gb / 2))
    if [ $gomaxprocs -gt $cpu_cores ]; then
        gomaxprocs=$cpu_cores
    fi
    gomaxprocs=$((gomaxprocs + 1))
    echo $gomaxprocs
}

GOMAXPROCS=$(calculate_gomaxprocs)

echo "✅ GOMAXPROCS has been set to $GOMAXPROCS based on your server's resources."

# Check if the file exists before attempting to remove it
if [ -f "/lib/systemd/system/ceremonyclient.service" ]; then
    rm /lib/systemd/system/ceremonyclient.service
    echo "ceremonyclient.service file removed."
else
    echo "ceremonyclient.service file does not exist. No action taken."
fi

sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremonyclient Service

[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$NODE_PATH
ExecStart=$EXEC_START
Environment="GOMAXPROCS=$GOMAXPROCS"
KillSignal=SIGINT
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF

### Build VDF
cd ~/ceremonyclient/vdf
./generate.sh

### Start the ceremonyclient service
echo "✅ Starting Ceremonyclient Service"
sudo systemctl daemon-reload
sudo systemctl enable ceremonyclient
sudo systemctl start ceremonyclient

sleep 5  # Add a 5-second delay
sudo journalctl -u ceremonyclient.service -f --no-hostname -o cat