#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "This tool checks various aspects of the environment of this machine and the Quilibrium node."
    echo ""
    echo "USAGE: bash ceremonyclient_env.sh [-h] [-x] [-env-init] [-env-update [-arch] [-os] [-key string]"
    echo "                                  [-latest-version 'node|qclient|'-'installed|release|'-'files|'-'quiet|']"
    echo ""
    echo "       -h                               Display this help dialogue."
    echo "       -x                               For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -env-init                        Initialise the .localenv file."
    echo "       -env -update                     Update the .localenv file."
    echo "       -arch                            Print the CPU architecture."
    echo "       -os                              Print the system OS."
    echo "       -key                             Check the .localenv for a key and print the corresponding value."
    echo "       -latest-version                  Print the latest versions of node & qclient binaries."
    echo "                                        Provide a string to thin down results: 'node|qclient|'-'installed|release|'-'files|'-'quiet|';"
    echo "                                        provide no string to get all options."
    echo ""
    exit 0
}

# Initialise the variables used in this script as zero/empty variables
CHECK_OS=""
CHECK_ARCH=""

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
node_latest_version_installed=
node_latest_version_released=
qclient_latest_version_installed=
qclient_latest_version_released=
peer_id=
node_release_url=
qclient_release_url=
EOF
    fi
}

LATEST_INSTALLED_VERSIONS_func() {
    local TYPE=$1

    # List all relevant files
    find $(PRINT_LOCAL_ENV_KEY_VALUE_func "ceremonyclient_root_dir") -type f -name "$TYPE-*-$RELEASE_LINE" | \
    # Extract the version numbers using grep and awk
    awk -F'-' '{sub(/-$RELEASE_LINE.*/, "", $2); print $2, $0}' | \
    # Sort by version numbers in descending order
    sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr | \
    # Take the first line (highest version)
    head -n 1 | \
    if [[ $FILES_REQUESTED = FALSE ]]; then awk -F' ' '{print $1}'; else awk -F' ' '{print $2}'; fi
}

LATEST_RELEASE_VERSIONS_func() {
    local TYPE=$1
    local RELEASE_URL=$2

    # List all relevant files
    curl -s -S $RELEASE_URL | grep $RELEASE_LINE | \
    # Extract the version numbers using grep and awk
    awk -F'-' '{sub(/-$RELEASE_LINE.*/, "", $2); print $2, $0}' | \
    # Sort by version numbers in descending order
    sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr | \
    # Take the first line (highest version)
    head -n 1 | \
    if [[ $FILES_REQUESTED = FALSE ]]; then awk -F' ' '{print $1}'; else awk -F' ' '{print $2}'; fi
}

LATEST_VERSIONS_func() {
    # Initialise options and their corresponding checkers
    local OPTIONS="${1:-}"
    local NODE_REQUESTED=FALSE
    local QCLIENT_REQUESTED=FALSE
    local INSTALLED_REQUESTED=FALSE
    local RELEASE_REQUESTED=FALSE
    local FILES_REQUESTED=FALSE
    local QUIET=FALSE

    # Check if no option is provided (i.e., show both node and qclient info)
    if [[ -z "$OPTIONS" || "$OPTIONS" == 'quiet' ]]; then
        NODE_REQUESTED=TRUE
        QCLIENT_REQUESTED=TRUE
        INSTALLED_REQUESTED=TRUE
        RELEASE_REQUESTED=TRUE
        FILES_REQUESTED=FALSE
        QUIET=TRUE
    else
        # Check for presence of 'node' or 'qclient' in the options
        if [[ ! "$OPTIONS" =~ "node" && ! "$OPTIONS" =~ "qclient" ]]; then NODE_REQUESTED=TRUE && QCLIENT_REQUESTED=TRUE; fi
        if [[ "$OPTIONS" =~ "node" ]]; then NODE_REQUESTED=TRUE; fi
        if [[ "$OPTIONS" =~ "qclient" ]]; then QCLIENT_REQUESTED=TRUE; fi
        # Check for presence of 'installed' or 'release' in the options
        if [[ ! "$OPTIONS" =~ "installed" && ! "$OPTIONS" =~ "release" ]]; then INSTALLED_REQUESTED=TRUE && RELEASE_REQUESTED=TRUE; fi
        if [[ "$OPTIONS" =~ "installed" ]]; then INSTALLED_REQUESTED=TRUE; fi
        if [[ "$OPTIONS" =~ "release" ]]; then RELEASE_REQUESTED=TRUE; fi
        # Check for presence of 'files' in the options
        if [[ "$OPTIONS" =~ "files" ]]; then FILES_REQUESTED=TRUE; fi
        # Check for presence of 'quiet' in the options
        if [[ "$OPTIONS" =~ "quiet" ]]; then QUIET=TRUE; fi
    fi

    local NODE_RELEASE_URL="https://releases.quilibrium.com/release"
    local QCLIENT_RELEASE_URL="https://releases.quilibrium.com/qclient-release"

    local LATEST_NODE_FILES_RELEASE=$(curl -s -S $NODE_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)
    local LATEST_QCLIENT_FILES_RELEASE=$(curl -s -S $QCLIENT_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)

    if [[ $FILES_REQUESTED = TRUE ]]; then
        local FILES_TEXT="files"
    else
        local FILES_TEXT="version"
    fi

    if [[ $NODE_REQUESTED = TRUE ]]; then
        local TYPE='node'

        if [[ $INSTALLED_REQUESTED = TRUE ]]; then
            local SOURCE='installed'
            if [[ $QUIET = TRUE ]]; then
                LATEST_INSTALLED_VERSIONS_func "$TYPE"
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_INSTALLED_VERSIONS_func "$TYPE")"
            fi
        fi
        if [[ $RELEASE_REQUESTED = TRUE ]]; then
            local SOURCE='release'
            if [[ $QUIET = TRUE ]]; then
                LATEST_RELEASE_VERSIONS_func "$TYPE" $NODE_RELEASE_URL
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_RELEASE_VERSIONS_func "$TYPE" $NODE_RELEASE_URL)"
            fi
        fi
    fi
    if [[ $QCLIENT_REQUESTED = TRUE ]]; then
        local TYPE='qclient'

        if [[ $INSTALLED_REQUESTED = TRUE ]]; then
            local SOURCE='installed'
            if [[ $QUIET = TRUE ]]; then
                LATEST_INSTALLED_VERSIONS_func "$TYPE"
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_INSTALLED_VERSIONS_func "$TYPE")"
            fi
        fi
        if [[ $RELEASE_REQUESTED = TRUE ]]; then
            local SOURCE='release'
            if [[ $QUIET = TRUE ]]; then
                LATEST_RELEASE_VERSIONS_func "$TYPE" $QCLIENT_RELEASE_URL
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_RELEASE_VERSIONS_func "$TYPE" $QCLIENT_RELEASE_URL)"
            fi
        fi
    fi
}



while TRUE; do
    case "$1" in
        -x) set -x;;
        -h) USAGE_func;;
        -env-init) INITIALISE_LOCAL_ENV_func;;
        -env-update) UPDATE_LOCAL_ENV_func;;
        -arch) CHECK_ARCH_func;;
        -os) CHECK_OS_func;;
        -key) PRINT_LOCAL_ENV_KEY_VALUE_func "$2";;
        -latest-version) LATEST_VERSIONS_func "${2:-}";;
        *) USAGE_func;;
    esac
    exit
done

exit 0