#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "This tool checks various aspects of the environment of this machine and the Quilibrium node."
    echo ""
    echo "USAGE: bash ceremonyclient_env.sh [-h] [-x] [-env-init] [-env-update [-arch] [-os] [-key]"
    echo "                                  [-latest-versions] [-latest-files]"
    echo ""
    echo "       -h                               Display this help dialogue."
    echo "       -x                               For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -env-init                        Initialise the .localenv file."
    echo "       -env -update                     Update the .localenv file."
    echo "       -arch                            Print the CPU architecture."
    echo "       -os                              Print the system OS."
    echo "       -key                             Check the .localenv for a key and print the corresponding value."
    echo "       -latest-versions                 Print the latest versions of node & qclient binaries."
    echo "       -latest-versions-files           Print the latest versions of node & qclient binaries as files (installed and available through release)."
    echo "       -latest-node-versions            Print the latest versions of node binaries."
    echo "       -latest-node-versions-files      Print the latest versions of node binaries as files (installed and available through release)."
    echo "       -latest-qclient-versions         Print the latest versions of qclient binaries."
    echo "       -latest-qclient-versions-files   Print the latest versions of qclient binaries as files (installed and available through release)."
    echo ""
    exit 0
}

# Initialise the variables used in this script as zero/empty variables
CHECK_OS=""
CHECK_ARCH=""
LATEST_VERSIONS_PRINT_FILES=""

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

RELEASE_OS=$(CHECK_OS_func)
RELEASE_ARCH=$(CHECK_ARCH_func)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

PRINT_LOCAL_ENV_KEY_VALUE_func() {
    # Check if the file exists
    if [[ ! -f .localenv ]]; then
        echo "Error: .localenv does not exist."
        return 1
    fi

    # Use grep to find the line and awk to extract the value
    local VALUE=$(grep "^$1=" .localenv | awk -F'=' '{print $2}')

    # Check if the key exists in the file
    if [[ -z "$VALUE" && $(grep -c "^$1=" .localenv) -eq 0 ]]; then
        echo "Error: Key '$1' not found in .localenv."
        return 1
    fi

    # Return the value
    echo "$VALUE"
}

INITIALISE_LOCAL_ENV_func() {
    if [[ -f .localenv && -s .localenv ]]; then
        echo ".localenv file already exists, contents printed below:"
        cat .localenv
        return 1
    else
        touch .localenv
        sudo tee .localenv > /dev/null <<EOF
ceremonyclient_root_dir=
ceremonyclient_node_dir=
ceremonyclient_config=
node_latest_installed=
node_latest_released=
qclient_latest_installed=
qclient_latest_released=
peer_id=
EOF
    fi
}

LATEST_INSTALLED_VERSIONS_func() {
    # List all relevant files
    find $(PRINT_LOCAL_ENV_KEY_VALUE_func "ceremonyclient_root_dir") -type f -name "$1-*-$RELEASE_LINE" | \
    # Extract the version numbers using grep and awk
    awk -F'-' '{sub(/-$RELEASE_LINE.*/, "", $2); print $2, $0}' | \
    # Sort by version numbers in descending order
    sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr | \
    # Take the first line (highest version)
    head -n 1 | \
    if [[ $LATEST_VERSIONS_PRINT_FILES == 0 ]]; then
        # Print the version number
        awk -F' ' '{print $1}'
    else
        # Print the full filename
        awk -F' ' '{print $2}'
    fi
}

LATEST_VERSIONS_func() {
    NODE_FILES_RELEASE_URL="https://releases.quilibrium.com/release"
    QCLIENT_FILES_RELEASE_URL="https://releases.quilibrium.com/qclient-release"

    LATEST_NODE_FILES_RELEASE=$(curl -s -S $NODE_FILES_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)
    LATEST_QCLIENT_FILES_RELEASE=$(curl -s -S $QCLIENT_FILES_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)
    
    NODE_VERSIONS_func() {
        if ! [[ -z $LATEST_NODE_FILES_RELEASE && $(echo "$LATEST_NODE_FILES_RELEASE" | grep *"node-.*-$RELEASE_OS-$RELEASE_ARCH"*) ]]; then
            if [[ $LATEST_VERSIONS_PRINT_FILES == 0 ]]; then
                LATEST_NODE_FILE_RELEASE=$(echo "$LATEST_NODE_FILES_RELEASE" | grep "^node-.*-$RELEASE_OS-$RELEASE_ARCH$" | awk -F'-' '{print $2}')
                echo "Latest node version (release): $LATEST_NODE_FILE_RELEASE"
                echo "Latest node version (installed): $(LATEST_INSTALLED_VERSIONS_func 'node')"
            else
                LATEST_NODE_FILE_RELEASE=$(echo "$LATEST_NODE_FILES_RELEASE" | grep "^node-.*-$RELEASE_OS-$RELEASE_ARCH$")
                echo "Latest node file (release): $LATEST_NODE_FILE_RELEASE"
                echo "Latest node file (installed): $(LATEST_INSTALLED_VERSIONS_func 'node')"
            fi
        else
            echo "Error: Trouble with the output of $NODE_FILES_RELEASE_URL for the LATEST_NODE_FILES_RELEASE variable."
            echo "Variable contents are below:"
            echo "$LATEST_NODE_FILES_RELEASE"
            return 1
        fi
    }

    QCLIENT_VERSIONS_func() {
        if ! [[ -z $LATEST_QCLIENT_FILES_RELEASE && $(echo "$LATEST_QCLIENT_FILES_RELEASE" | grep *"qclient-.*-$RELEASE_OS-$RELEASE_ARCH"*) ]]; then
            if [[ $LATEST_VERSIONS_PRINT_FILES == 0 ]]; then
                LATEST_QCLIENT_FILE_RELEASE=$(echo "$LATEST_QCLIENT_FILES_RELEASE" | grep "^qclient-.*-$RELEASE_OS-$RELEASE_ARCH$" | awk -F'-' '{print $2}')
                echo "Latest qclient version (release): $LATEST_QCLIENT_FILE_RELEASE"
                echo "Latest qclient version (installed): $(LATEST_INSTALLED_VERSIONS_func 'qclient')"
            else
                LATEST_QCLIENT_FILE_RELEASE=$(echo "$LATEST_QCLIENT_FILES_RELEASE" | grep "^qclient-.*-$RELEASE_OS-$RELEASE_ARCH$")
                echo "Latest qclient file (release): $LATEST_QCLIENT_FILE_RELEASE"
                echo "Latest qclient file (installed): $(LATEST_INSTALLED_VERSIONS_func 'qclient')"
            fi
        else
            echo "Error: Trouble with the output of $QCLIENT_FILES_RELEASE_URL for the LATEST_QCLIENT_FILES_RELEASE variable."
            echo "Variable contents are below:"
            echo "$LATEST_QCLIENT_FILES_RELEASE"
            return 1
        fi
    }

    if [[ -z "${1:-}" ]]; then
        NODE_VERSIONS_func
        QCLIENT_VERSIONS_func
    elif [[ "$1" == "node" ]]; then
        NODE_VERSIONS_func
    elif [[ "$1" == "qclient" ]]; then
        QCLIENT_VERSIONS_func
    fi
}



while true; do
    case "$1" in
        -x) set -x;;
        -h) USAGE_func;;
        -env-init) INITIALISE_LOCAL_ENV_func;;
        -env-update) UPDATE_LOCAL_ENV_func;;
        -arch) CHECK_ARCH_func;;
        -os) CHECK_OS_func;;
        -key) CHECK_LOCAL_ENV_KEY_func "$OPTARG";;
        -latest-versions) LATEST_VERSIONS_PRINT_FILES="0"; LATEST_VERSIONS_func;;
        -latest-versions-files) LATEST_VERSIONS_PRINT_FILES="1"; LATEST_VERSIONS_func;;
        -latest-node-versions) LATEST_VERSIONS_PRINT_FILES="0"; LATEST_VERSIONS_func 'node';;
        -latest-qclient-versions) LATEST_VERSIONS_PRINT_FILES="0"; LATEST_VERSIONS_func 'qclient';;
        -latest-node-versions-files) LATEST_VERSIONS_PRINT_FILES="1"; LATEST_VERSIONS_func 'node';;
        -latest-qclient-versions-files) LATEST_VERSIONS_PRINT_FILES="1"; LATEST_VERSIONS_func 'qclient';;
        *) USAGE_func;;
    esac
    exit
done

exit 0