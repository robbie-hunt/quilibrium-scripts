#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Tool to download Quilibrium binaries by supplying a filename or pattern via -f."
    echo ""
    echo "USAGE: bash ceremonyclient_download.sh [-h] [-x] [-q] [-f] [-a]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q    Quiet mode."
    echo "       -f    Specific node/qclient files to download."
    echo "             Only supply a filename, not a filetype, e.g. 'node-2.0.5.1-darwin-arm64'."
    echo "       -d    (Optional) Directory to install binaries to."
    echo "             By default, the directory for install is determined by the 'ceremonyclient_node_dir' key in .localenv."
    echo ""
    exit 0
}

# Function to fetch the files from quilibrium.com
FETCH_FILES_func() {
    if [[ ! $(curl -s -S "$URL" | grep -s "$FILE_PATTERN") ]]; then
        if [[ "$QUIET" == 1 ]]; then
            return 1
        else
            echo "Error: no release files relating to $FILE_PATTERN could be found."
            echo "This could be due to network issues, a bad spelling provided to -f, or trouble connecting to $URL."
            return 1
        fi
    fi

    RELEASE_FILES_AVAILABLE=$(curl -s -S "$URL" | grep "$FILE_PATTERN")

    for RELEASE_FILE in $RELEASE_FILES_AVAILABLE; do
        if curl -s -S "https://releases.quilibrium.com/$RELEASE_FILE" > "$CEREMONYCLIENT_NODE_DIR/$RELEASE_FILE"; then
            if [[ "$QUIET" == 1 ]]; then
                :
            else
                echo "Downloaded file $RELEASE_FILE"
            fi
        fi
    done
}

# Function to roughly check filesizes to make sure they downloaded correctly
# Makes the main node/qclient binary executable too
CHECK_FILESIZES_MAKE_EXECUTABLE_func() {
    local FILES_TO_CHECK="$1"

    for FILE in $FILES_TO_CHECK; do
        if [[ "$FILE" =~ ".dgst" ]]; then
            # Check that the .dgst and .sg files are above 100 bytes
            if [[ -n $(find "$FILE" -prune -size +100c) ]]; then
                :
            else
                if [[ "$QUIET" == 1 ]]; then
                    return 1
                else
                    echo "Error: file '$FILE' has size of '$(du -h "$FILE")'."
                    echo "Check manually to make sure this file downloaded correctly before using it."
                    return 1
                fi
            fi
        else
            # Check that the main node/qclient binary ar above 180MB
            if [[ -n $(find "$FILE" -prune -size +180000000c) ]]; then
                chmod +x "$FILE"
            else
                if [[ "$QUIET" == 1 ]]; then
                    return 1
                else
                    echo "Error: file '$FILE' has size of '$(du -h "$FILE")'."
                    echo "Check manually to make sure this file downloaded correctly before using it."
                    return 1
                fi
            fi
        fi
    done
}

# Double-checks that the files downloaded are the same as the files available from quilibrium.com
CONFIRM_NEW_BINARIES_func() {
    NEW_LATEST_FILE_INSTALLED_PATH=$(./ceremonyclient_env.sh -latest-version "$TYPE-installed-files-quiet")
    NEW_LATEST_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)
    NEW_LATEST_FILES=$(find "$CEREMONYCLIENT_NODE_DIR" -type f -name "$NEW_LATEST_FILE_INSTALLED_FILENAME*")

    if [[ "$NEW_LATEST_FILE_INSTALLED_FILENAME" == "$LATEST_VERSION_RELEASED" ]]; then
        if CHECK_FILESIZES_MAKE_EXECUTABLE_func "$NEW_LATEST_FILES"; then
            if [[ "$QUIET" == 1 ]]; then
                :
            else
                echo "${TYPE^} binaries installed successfully."
            fi
        else
            if [[ "$QUIET" == 1 ]]; then
                return 1
            else
                echo "Error: CHECK_FILESIZES_MAKE_EXECUTABLE_func function failed."
                echo "Manually check the file sizes in $CEREMONYCLIENT_NODE_DIR of the files downloaded below:"
                echo "$NEW_LATEST_FILES"
                return 1
            fi
        fi
    fi
}

# Function to run the whole download operation
DOWNLOAD_AND_CONFIRM_func() {
    FETCH_FILES_func "$1"
    CONFIRM_NEW_BINARIES_func
}


# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

# Supply a node directory using the -d flag
DIRECTORY=0

while getopts "xhqf:d:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        f) FILE_PATTERN="$OPTARG";;
        d) DIRECTORY="$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

# For the ceremonyclient node directory
# If a directory was supplied via the -d option, use it
# Otherwise, use the directory in the .localenv
if [[ -z "$DIRECTORY" ]]; then
    CEREMONYCLIENT_NODE_DIR=$(./ceremonyclient_env.sh -key "ceremonyclient_node_dir")
else
    CEREMONYCLIENT_NODE_DIR="$DIRECTORY"
fi

# Make sure the ceremonyclient node dir that will be used actually exists
if [[ -d "$CEREMONYCLIENT_NODE_DIR" && -G "$CEREMONYCLIENT_NODE_DIR" ]]; then
    :
else
    echo "Error: $CEREMONYCLIENT_NODE_DIR cannot be used for the install of binaries."
    echo "Directory either does not exist, or is not usable by this user."
    exit 1
fi

# Type of binaries - node or qclient
TYPE=$(echo "$FILE_PATTERN" | awk -F'-' '{print $1}')
# 'node_release_url' or 'qclient_release_url'
TYPE_AS_KEY=$(echo $TYPE"_release_url")
# URL to fetch files from
URL=$(./ceremonyclient_env.sh -key "$TYPE_AS_KEY")

# Get the filename (and path, for the installed binary) of the latest version of the main qclient/node binary
LATEST_VERSION_INSTALLED=$(./ceremonyclient_env.sh -latest-version "$TYPE-installed-files-quiet")
LATEST_VERSION_RELEASED=$(./ceremonyclient_env.sh -latest-version "$TYPE-release-files-quiet")

DOWNLOAD_AND_CONFIRM_func "$FILE_PATTERN"

exit 0