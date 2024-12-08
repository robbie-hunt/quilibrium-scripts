#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "This tool checks the environment of this machine, for Quilibrium script usage."
    echo ""
    echo "USAGE: bash ceremonyclient_env.sh [-h] [-x] [-a] [-o]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -i    Initialise the .localenv file."
    echo "       -a    Print the CPU architecture."
    echo "       -o    Print the system OS."
    echo "       -d    Print the ceremonyclient directory."
    echo ""
    exit 0
}

# Initialise the variables used in this script as zero/empty variables
CHECK_OS=""
CHECK_ARCH=""

while getopts "hxao" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func;;
        i) INITIALISE_LOCAL_ENV_func;;
        u) UPDATE_LOCAL_ENV_func;;
        a) CHECK_ARCH_func;;
        o) CHECK_OS_func;;
        d) PRINT_CEREMONYCLIENT_DIR_func;;
    esac
done
shift $((OPTIND -1))



INITIALISE_LOCAL_ENV_func() {
    if [[ -f .localenv && -s .localenv ]]; then
        echo ".localenv file already exists, contents printed below:"
        cat .localenv
        return 1
    else
        touch .localenv
        sudo tee .localenv > /dev/null <<EOF
ceremonyclient_root_dir=
node_latest_installed=
node_latest_released=
qclient_latest_installed=
qclient_latest_released=
peer_id=
EOF
    fi
}

CHECK_ARCH_func() {
    RELEASE_ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ "$RELEASE_ARCH" = "x86_64" ]]; then
        echo "$RELEASE_ARCH"
    elif [[ "$RELEASE_ARCH" = "aarch64" || "$RELEASE_ARCH" = "arm64" ]]; then
        RELEASE_ARCH="arm64"
        echo "$RELEASE_ARCH"
    else
        echo "Error: couldn't match CPU arch '$RELEASE_ARCH' to a viable Quil CPU arch."
        echo "Please check this yourself by running \`uname -m | tr '[:upper:]' '[:lower:]'\`."
        exit 1
    fi
}

CHECK_OS_func() {
    RELEASE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ "$RELEASE_OS" = "linux" ]]; then
        echo "$RELEASE_OS"
    elif [[ "$RELEASE_OS" = "darwin" ]]; then
        echo "$RELEASE_OS"
    else
        echo "Error: couldn't match OS '$RELEASE_OS' to available OS's for Quil."
        echo "Please check this yourself by running \`uname -s | tr '[:upper:]' '[:lower:]'\`."
        exit 1
    fi
}

PRINT_CEREMONYCLIENT_DIR_func() {

}

exit 0