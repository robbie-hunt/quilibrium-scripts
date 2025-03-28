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
    echo "       -q    Quiet mode."
    echo "       -g    Install the Golang gRPC package."
    echo "       -l    Set up local gRPC on a node."
    echo "       -p    Set up public gRPC (without a node; just qclient)."
    echo ""
    echo "To setup gRPC on a Quil node, run the command using the -g option,"
    echo "then run it using the -l option, then again using the -p option."
    echo ""
    exit 0
}

# Function to check if a line exists in a file
LINE_EXISTS_func() {
    grep -qF "$1" "$2"
    return
}

# Function to add a line after a specific pattern
ADD_LINE_AFTER_PATTERN_func() {
#    sudo sed -i -E "/^ *$1:/a\ $2" "$3"
    sudo sed -i -E "/^ *$1:/a\
  $2
" "$3"
    return
}

INSTALL_GO_GRPC_PACKAGE_func() {
    if [[ "$RELEASE_OS" == 'darwin' ]]; then
        if [[ $(brew --version) ]]; then
            brew install grpcurl
        else
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"  
            # Get homebrew commands working
            tee -a ~/.zshrc > /dev/null <<EOF

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"



EOF
            . ~/.zshrc
            brew install grpcurl
        fi
    elif [[ "$RELEASE_OS" == 'linux' ]]; then
        go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
    fi
    return
}

# Function to check and modify listenMultiaddr
CHECK_MODIFY_LISTEN_MULTIADDR_func() {
    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Checking listenMultiaddr..."
    fi
    
    # Using more flexible pattern matching with grep
    if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic" $CEREMONYCLIENT_CONFIG; then
        if [[ $QUIET == 1 ]]; then
            :
        else
            echo "Modifying listenMultiaddr..."
        fi
        # Using perl-compatible regex for more reliable replacement
        sudo sed -i -E 's|^([[:space:]]*)listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/udp/8336/quic.*$|\1listenMultiaddr: /ip4/0.0.0.0/tcp/8336|' $CEREMONYCLIENT_CONFIG
        
        if [ $? -eq 0 ]; then
            if [[ $QUIET == 1 ]]; then
                :
            else
                echo "listenMultiaddr modified to use TCP protocol."
            fi
        else
            if [[ $QUIET == 1 ]]; then
                :
            else
                echo "Error: Failed to modify listenMultiaddr. Please check manually your config.yml file."
            fi
            return 1
        fi
    else
        # Check for new TCP configuration
        if grep -q "^[[:space:]]*listenMultiaddr:[[:space:]]*/ip4/0\.0\.0\.0/tcp/8336" $CEREMONYCLIENT_CONFIG; then
            if [[ $QUIET == 1 ]]; then
                :
            else
                echo "New listenMultiaddr line found."
            fi
        else
            if [[ $QUIET == 1 ]]; then
                :
            else
                echo "Error: Neither old nor new listenMultiaddr found. This could cause issues."
                echo "Please manually check your config.yml file: $CEREMONYCLIENT_CONFIG."
            fi
            return 1
        fi
    fi
    return
}

# Function to set up local gRPC
SETUP_LOCAL_GRPC_func() {
    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Setting up local gRPC and REST..."
    fi

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i -E 's|^listenGrpcMultiaddr: \"\"|listenGrpcMultiaddr: \"/ip4/127.0.0.1/tcp/8337\"|' $CEREMONYCLIENT_CONFIG
    sudo sed -i -E 's|^listenRESTMultiaddr: \"\"|listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"|' $CEREMONYCLIENT_CONFIG

    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Local gRPC and REST setup completed."
        echo "If you were on public RPC previously and received errors when querying your -node-info,"
        echo "you should now restart your node and let it sync."
    fi
    return 0
}

# Function to set up alternative gRPC (blank gRPC, local REST)
SETUP_PUBLIC_GRPC_func() {
    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Setting up public gRPC..."
    fi

    # Delete existing lines for listenGrpcMultiaddr and listenRESTMultiaddr if they exist
    sudo sed -i '/^ *listenGrpcMultiaddr:/d' $CEREMONYCLIENT_CONFIG
    sudo sed -i '/^ *listenRESTMultiaddr:/d' $CEREMONYCLIENT_CONFIG

    # Add blank gRPC and local REST settings
    echo "listenGrpcMultiaddr: \"\"" | sudo tee -a $CEREMONYCLIENT_CONFIG > /dev/null || { if [[ $QUIET == 1 ]]; then :; else echo "Failed to set blank gRPC. Exiting..."; fi; return 1; }
    echo "listenRESTMultiaddr: \"/ip4/127.0.0.1/tcp/8338\"" | sudo tee -a $CEREMONYCLIENT_CONFIG > /dev/null || { if [[ $QUIET == 1 ]]; then :; else echo "Failed to set REST. Exiting..."; fi; return 1; }

    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Alternative gRPC setup completed (blank gRPC, local REST)."
    fi
    return 0
}

# Function to setup stats collection
SETUP_STATS_COLLECTION_func() {
    if [[ $QUIET == 1 ]]; then
        :
    else
        echo "Enabling stats collection..."
    fi
    if ! LINE_EXISTS_func "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" $CEREMONYCLIENT_CONFIG; then
        ADD_LINE_AFTER_PATTERN_func "engine" "statsMultiaddr: \"/dns/stats.quilibrium.com/tcp/443\"" $CEREMONYCLIENT_CONFIG
        if [[ $QUIET == 1 ]]; then
            :
        else
            echo "Stats collection enabled."
        fi
    else
        if [[ $QUIET == 1 ]]; then
            :
        else
            echo "Stats collection already enabled."
        fi
    fi
    return 0
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

CEREMONYCLIENT_CONFIG=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key 'ceremonyclient_config')

echo "CEREMONYCLIENT_CONFIG = $CEREMONYCLIENT_CONFIG"

RELEASE_ARCH=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

while getopts "xhqglp" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func;;
        q) QUIET=1;;
        g) INSTALL_GO_GRPC_PACKAGE_func;;
        l)
            SETUP_LOCAL_GRPC_func
            SETUP_STATS_COLLECTION_func
            echo -e "\nConfiguration of local gRPC & REST complete."
            ;;
        p)
            SETUP_PUBLIC_GRPC_func
            SETUP_STATS_COLLECTION_func
            echo -e "\nConfiguration of public gRPC complete."
            ;;
        *) USAGE_func;;
    esac
done
shift $((OPTIND -1))

exit