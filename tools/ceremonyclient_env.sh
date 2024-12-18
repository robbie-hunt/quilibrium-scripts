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
    echo "       -env-update                      Update the .localenv file."
    echo "       -arch                            Print the CPU architecture."
    echo "       -os                              Print the system OS."
    echo "       -release-line                    Print the CPU architecture and system OS in the format 'os-arch'."
    echo "       -key                             Check the .localenv for a key and print the corresponding value."
    echo "       -latest-version                  Print the latest versions of node & qclient binaries."
    echo "                                        Provide a string to thin down results: 'node|qclient|'-'installed|release|'-'files|'-'quiet|'."
    echo "                                        Provide no string to get all options."
    echo ""
    exit 0
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

LOCALENV="$SCRIPT_ROOT_DIR/.localenv"

PRINT_ARCH_func() {
    RELEASE_ARCH=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ "$RELEASE_ARCH" = "x86_64" || "$RELEASE_ARCH" == "amd64" ]]; then
        RELEASE_ARCH="amd64"
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

PRINT_OS_func() {
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

RELEASE_OS=$(PRINT_OS_func)
RELEASE_ARCH=$(PRINT_ARCH_func)

PRINT_RELEASE_LINE_func() {
    echo "$RELEASE_OS-$RELEASE_ARCH"
}

RELEASE_LINE=$(PRINT_RELEASE_LINE_func)

PRINT_LOCAL_ENV_KEY_VALUE_func() {
    # Check if the file exists
    if [[ -f "$LOCALENV" ]]; then
        :
    else
        echo "Error: $LOCALENV does not exist."
        return 1
    fi

    # Use grep to find the line and awk to extract the value
    local VALUE=$(grep "^$1=" $LOCALENV | awk -F'=' '{print $2}')

    # Check if the key exists in the file
    if [[ -z "$VALUE" && $(grep -c "^$1=" $LOCALENV) -eq 0 ]]; then
        echo "Error: Key '$1' not found in $LOCALENV."
        return 1
    fi

    # Return the value
    echo "$VALUE"
}

INITIALISE_LOCAL_ENV_func() {
    if [[ -f "$LOCALENV" && -s "$LOCALENV" ]]; then
        echo "$LOCALENV file already exists, contents printed below:"
        cat "$LOCALENV"
        return 1
    else
        touch "$LOCALENV"
        sudo tee "$LOCALENV" > /dev/null <<EOF
ceremonyclient_root_dir=
ceremonyclient_node_dir=
ceremonyclient_config=
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
    if [[ $FILES_REQUESTED = 0 ]]; then awk -F' ' '{print $1}'; else awk -F' ' '{print $2}'; fi
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
    if [[ $FILES_REQUESTED = 0 ]]; then awk -F' ' '{print $1}'; else awk -F' ' '{print $2}'; fi
}

LATEST_VERSIONS_func() {
    # Initialise options and their corresponding checkers
    local OPTIONS="${1:-}"
    local NODE_REQUESTED=0
    local QCLIENT_REQUESTED=0
    local INSTALLED_REQUESTED=0
    local RELEASE_REQUESTED=0
    local FILES_REQUESTED=0
    local QUIET=0

    # Check if no option is provided (i.e., show both node and qclient info)
    if [[ -z "$OPTIONS" ]]; then
        NODE_REQUESTED=1
        QCLIENT_REQUESTED=1
        INSTALLED_REQUESTED=1
        RELEASE_REQUESTED=1
        FILES_REQUESTED=0
        QUIET=0
    else
        # Check for presence of 'node' or 'qclient' in the options
        if [[ ! "$OPTIONS" =~ "node" && ! "$OPTIONS" =~ "qclient" ]]; then NODE_REQUESTED=1 && QCLIENT_REQUESTED=1; fi
        if [[ "$OPTIONS" =~ "node" ]]; then NODE_REQUESTED=1; fi
        if [[ "$OPTIONS" =~ "qclient" ]]; then QCLIENT_REQUESTED=1; fi
        # Check for presence of 'installed' or 'release' in the options
        if [[ ! "$OPTIONS" =~ "installed" && ! "$OPTIONS" =~ "release" ]]; then INSTALLED_REQUESTED=1 && RELEASE_REQUESTED=1; fi
        if [[ "$OPTIONS" =~ "installed" ]]; then INSTALLED_REQUESTED=1; fi
        if [[ "$OPTIONS" =~ "release" ]]; then RELEASE_REQUESTED=1; fi
        # Check for presence of 'files' in the options
        if [[ "$OPTIONS" =~ "files" ]]; then FILES_REQUESTED=1; fi
        # Check for presence of 'quiet' in the options
        if [[ "$OPTIONS" =~ "quiet" ]]; then QUIET=1; fi
    fi

    local NODE_RELEASE_URL="https://releases.quilibrium.com/release"
    local QCLIENT_RELEASE_URL="https://releases.quilibrium.com/qclient-release"

    local LATEST_NODE_FILES_RELEASE=$(curl -s -S $NODE_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)
    local LATEST_QCLIENT_FILES_RELEASE=$(curl -s -S $QCLIENT_RELEASE_URL | grep $RELEASE_OS-$RELEASE_ARCH)

    if [[ $FILES_REQUESTED = 1 ]]; then
        local FILES_TEXT="files"
    else
        local FILES_TEXT="version"
    fi

    if [[ $NODE_REQUESTED = 1 ]]; then
        local TYPE='node'

        if [[ $INSTALLED_REQUESTED = 1 ]]; then
            local SOURCE='installed'
            if [[ $QUIET = 1 ]]; then
                LATEST_INSTALLED_VERSIONS_func "$TYPE"
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_INSTALLED_VERSIONS_func "$TYPE")"
            fi
        fi
        if [[ $RELEASE_REQUESTED = 1 ]]; then
            local SOURCE='release'
            if [[ $QUIET = 1 ]]; then
                LATEST_RELEASE_VERSIONS_func "$TYPE" $NODE_RELEASE_URL
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_RELEASE_VERSIONS_func "$TYPE" $NODE_RELEASE_URL)"
            fi
        fi
    fi
    if [[ $QCLIENT_REQUESTED = 1 ]]; then
        local TYPE='qclient'

        if [[ $INSTALLED_REQUESTED = 1 ]]; then
            local SOURCE='installed'
            if [[ $QUIET = 1 ]]; then
                LATEST_INSTALLED_VERSIONS_func "$TYPE"
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_INSTALLED_VERSIONS_func "$TYPE")"
            fi
        fi
        if [[ $RELEASE_REQUESTED = 1 ]]; then
            local SOURCE='release'
            if [[ $QUIET = 1 ]]; then
                LATEST_RELEASE_VERSIONS_func "$TYPE" $QCLIENT_RELEASE_URL
            else
                echo "Latest $TYPE $FILES_TEXT ($SOURCE): $(LATEST_RELEASE_VERSIONS_func "$TYPE" $QCLIENT_RELEASE_URL)"
            fi
        fi
    fi
}



while :; do
    case "$1" in
        -x) set -x;;
        -h) USAGE_func;;
        -env-init) INITIALISE_LOCAL_ENV_func;;
        -env-update) UPDATE_LOCAL_ENV_func;;
        -arch) PRINT_ARCH_func;;
        -os) PRINT_OS_func;;
        -release-line) PRINT_RELEASE_LINE_func;;
        -key) PRINT_LOCAL_ENV_KEY_VALUE_func "$2";;
        -latest-version) LATEST_VERSIONS_func "${2:-}";;
        *) USAGE_func;;
    esac
    exit
done

exit 0