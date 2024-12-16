#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

# Determine the ExecStart line based on the architecture
ARCH=$(uname -m)
OS=$(uname -s)
RELEASE_LINE=$(./tools/ceremonyclient_env.sh -release-line)

VERSIONS=$(./tools/ceremonyclient_env.sh -latest-version 'release-quiet')
NODE_VERSION=$(echo "$VERSIONS" | sed '1q;d')
QCLIENT_VERSION=$(echo "$VERSIONS" | sed '2q;d')



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