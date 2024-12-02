#!/bin/bash


### FUNCTIONS

# Function to check if a line exists in a file
line_exists() {
    grep -qF "$1" "$2"
}

# Function to add a line after a specific pattern
add_line_after_pattern() {
    sudo sed -i "/^ *$1:/a\  $2" "$3" || { echo "Failed to add line after '$1'. Exiting..."; exit 1; }
}

# Function to check and modify listenMultiaddr
check_modify_listen_multiaddr() {
    echo "Checking listenMultiaddr..."
    
    # Using more flexible pattern matching with grep
    if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic" .config/config.yml; then
        echo "Modifying listenMultiaddr...
        # Using perl-compatible regex for more reliable replacement
        sudo sed -i -E 's|^([[:space:]]*)listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic.*$|\1listenMultiaddr: /ip4/0.0.0.0/tcp/8336|' .config/config.yml
        
        if [ $? -eq 0 ]; then
            echo "listenMultiaddr modified to use TCP protocol."
        else
            echo "Failed to modify listenMultiaddr. Please check manually your config.yml file"
        fi
    else
        # Check for new TCP configuration
        if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/tcp/8336" .config/config.yml; then
            echo "New listenMultiaddr line found."
        else
            echo "Neither old nor new listenMultiaddr found. This could cause issues. Please manually check your config.yml file"
        fi
    fi
}

# Function to set up local gRPC
setup_local_grpc() {
    echo "Enabling local gRPC and REST..."
    sleep 1
    cd "$HOME/ceremonyclient/node" || { echo "Failed to change directory to ~/ceremonyclient/node. Exiting..."; exit 1; }

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i '/^ *listenGrpcMultiaddr:/d' .config/config.yml
    sudo sed -i '/^ *listenRESTMultiaddr:/d' .config/config.yml

    # Add listenGrpcMultiaddr: "/ip4/127.0.0.1/tcp/8337"
    echo "listenGrpcMultiaddr: \"/ip4/127.0.0.1/tcp/8337\"" | sudo tee -a .config/config.yml > /dev/null || { echo "Failed to enable gRPC. Exiting..."; exit 1; }

    # Add listenRESTMultiaddr: "/ip4/127.0.0.1/tcp/8338"
    echo "listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"" | sudo tee -a .config/config.yml > /dev/null || { echo "Failed to enable REST. Exiting..."; exit 1; }

    echo "Local gRPC and REST setup completed."
    echo "If you where on public RPC previously, and receive errors when querying your -node-info,"
    echo "You should now restart your node and let it run until it begins to sync."
    return 0
}

# Function to set up alternative gRPC (blank gRPC, local REST)
setup_public_grpc() {
    echo "Setting up alternative gRPC configuration..."
    sleep 1
    cd "$HOME/ceremonyclient/node" || { echo "Failed to cd into ~/ceremonyclient/node. Exiting..."; exit 1; }

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i '/^ *listenGrpcMultiaddr:/d' .config/config.yml
    sudo sed -i '/^ *listenRESTMultiaddr:/d' .config/config.yml

    # Add blank gRPC and local REST settings
    echo "listenGrpcMultiaddr: \"\"" | sudo tee -a .config/config.yml > /dev/null || { echo "Failed to set blank gRPC. Exiting..."; exit 1; }
    echo "listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"" | sudo tee -a .config/config.yml > /dev/null || { echo "Failed to set REST. Exiting..."; exit 1; }

    echo "Alternative gRPC setup completed (blank gRPC, local REST)."
    return 0
}

# Function to setup stats collection
setup_stats_collection() {
    echo "Enabling stats collection..."
    if ! line_exists "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" .config/config.yml; then
        add_line_after_pattern "engine" "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" .config/config.yml
        echo "Stats collection enabled."
    else
        echo "Stats collection already enabled."
    fi
}



### MAIN MENU

while true; do
    echo ""
    echo -e "\nPlease select a setup option:"
    echo ""
    echo "1) Setup local gRPC"
    echo "   Choose if you are running a node."
    echo ""
    echo "2) Setup public gRPC"
    echo "   Choose if you want to run the Qclient without having a working node."
    echo ""
    read -r choice
    echo ""

    case $choice in
        1)
            setup_local_grpc
            setup_stats_collection
            #check_modify_listen_multiaddr
            echo -e "\nConfiguration complete. You can check your settings with:"
            echo "cd $HOME/ceremonyclient/node/.config/ && cat config.yml"
            exit 0
            ;;
        2)
            setup_public_grpc
            setup_stats_collection
            #check_modify_listen_multiaddr
            echo -e "\nConfiguration complete. You can check your settings with:"
            echo "cd $HOME/ceremonyclient/node/.config/ && cat config.yml"
            exit 0
            ;;
        *)
            echo "Invalid option. Please select 1 or 2."
            continue  # Continue the loop for invalid input
            ;;
    esac
done