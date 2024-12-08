#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "This script sets up gRPC for a Quilibrium node."
    echo ""
    echo "USAGE: bash ceremonyclient_grpc.sh [-h] [-x] [-l] [-p]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -l    Set up local gRPC on a node."
    echo "       -p    Run public gRPC (without a node; just qclient).."
    echo ""
    exit 0
}

CEREMONYCLIENT_CONFIG=$(./ceremonyclient_env.sh -key 'ceremonyclient_config')

# Function to check if a line exists in a file
LINE_EXISTS_func_func() {
    grep -qF "$1" "$2"
}

# Function to add a line after a specific pattern
ADD_LINE_AFTER_PATTERN_func() {
    sudo sed -i "/^ *$1:/a\  $2" "$3" || { echo "Failed to add line after '$1'. Exiting..."; exit 1; }
}

INSTALL_GO_GRPC_PACKAGE_func() {
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
}

# Function to check and modify listenMultiaddr
CHECK_MODIFY_LISTEN_MULTIADDR_func() {
    echo "Checking listenMultiaddr..."
    
    # Using more flexible pattern matching with grep
    if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic" '$CEREMONYCLIENT_CONFIG'; then
        echo "Modifying listenMultiaddr..."
        # Using perl-compatible regex for more reliable replacement
        sudo sed -i -E 's|^([[:space:]]*)listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic.*$|\1listenMultiaddr: /ip4/0.0.0.0/tcp/8336|' '$CEREMONYCLIENT_CONFIG'
        
        if [ $? -eq 0 ]; then
            echo "listenMultiaddr modified to use TCP protocol."
        else
            echo "Error: Failed to modify listenMultiaddr. Please check manually your config.yml file."
            return 1
        fi
    else
        # Check for new TCP configuration
        if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/tcp/8336" '$CEREMONYCLIENT_CONFIG'; then
            echo "New listenMultiaddr line found."
        else
            echo "Error: Neither old nor new listenMultiaddr found. This could cause issues."
            echo "Please manually check your config.yml file: $CEREMONYCLIENT_CONFIG."
            return 1
        fi
    fi
}

# Function to set up local gRPC
SETUP_LOCAL_GRPC_func() {
    echo "Setting up local gRPC and REST..."
    sleep 1

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i -E 's|^listenGrpcMultiaddr: \"\"|listenGrpcMultiaddr: \"/ip4/127.0.0.1/tcp/8337\"|' '$CEREMONYCLIENT_CONFIG'
    sudo sed -i -E 's|^listenRESTMultiaddr: \"\"|listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"|' '$CEREMONYCLIENT_CONFIG'

    echo "Local gRPC and REST setup completed."
    echo "If you were on public RPC previously and received errors when querying your -node-info,"
    echo "you should now restart your node and let it sync."
    return 0
}

# Function to set up alternative gRPC (blank gRPC, local REST)
SETUP_PUBLIC_GRPC_func() {
    echo "Setting up public gRPC..."
    sleep 1

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i '/^ *listenGrpcMultiaddr:/d' '$CEREMONYCLIENT_CONFIG'
    sudo sed -i '/^ *listenRESTMultiaddr:/d' '$CEREMONYCLIENT_CONFIG'

    # Add blank gRPC and local REST settings
    echo "listenGrpcMultiaddr: \"\"" | sudo tee -a '$CEREMONYCLIENT_CONFIG' > /dev/null || { echo "Failed to set blank gRPC. Exiting..."; exit 1; }
    echo "listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"" | sudo tee -a '$CEREMONYCLIENT_CONFIG' > /dev/null || { echo "Failed to set REST. Exiting..."; exit 1; }

    echo "Alternative gRPC setup completed (blank gRPC, local REST)."
    return 0
}

# Function to setup stats collection
SETUP_STATS_COLLECTION_func() {
    echo "Enabling stats collection..."
    if ! LINE_EXISTS_func "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" '$CEREMONYCLIENT_CONFIG'; then
        ADD_LINE_AFTER_PATTERN_func "engine" "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" '$CEREMONYCLIENT_CONFIG'
        echo "Stats collection enabled."
    else
        echo "Stats collection already enabled."
    fi
}



while getopts "xhlp" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func;;
        l)
            INSTALL_GO_GRPC_PACKAGE_func
            SETUP_PUBLIC_GRPC_func
            SETUP_STATS_COLLECTION_func
            echo -e "\nConfiguration of local gRPC & REST complete."
            ;;
        p)
            INSTALL_GO_GRPC_PACKAGE_func
            SETUP_PUBLIC_GRPC_func
            SETUP_STATS_COLLECTION_func
            echo -e "\nConfiguration of public gRPC complete."
            ;;
        *) USAGE_func;;
    esac
done
shift $((OPTIND -1))

exit 0