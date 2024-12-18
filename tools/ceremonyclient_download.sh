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
    echo "       -f    Specific node/qclient files to download. Only supply a filename, not a filetype, e.g. 'node-2.0.5.1-darwin-arm64'."
    echo ""
    exit 0
}

QUIET=0

RELEASE_ARCH=$(./tools/ceremonyclient_env.sh -arch)
RELEASE_OS=$(./tools/ceremonyclient_env.sh -os)
RELEASE_LINE="$RELEASE_OS-$RELEASE_ARCH"

CEREMONYCLIENT_NODE_DIR=$(./tools/ceremonyclient_env.sh -key "ceremonyclient_node_dir")

LATEST_VERSIONS=$(./tools/ceremonyclient_env.sh -latest-version 'files-quiet')
LATEST_NODE_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '1q;d')
LATEST_NODE_RELEASE=$(echo "$LATEST_VERSIONS" | sed '2q;d')
LATEST_QCLIENT_INSTALLED=$(echo "$LATEST_VERSIONS" | sed '3q;d')
LATEST_QCLIENT_RELEASE=$(echo "$LATEST_VERSIONS" | sed '4q;d')

# Download the files
# Check the filesizes of downloaded files
# Confirm the downloaded binary matches the latest version

FETCH_FILES_func() {
    local FILE_PATTERN="$1"
    local TYPE="$(echo $FILE_PATTERN | awk -F'-' '{print $1}')_release_url"
    local URL=$(./tools/ceremonyclient_env.sh -key $TYPE)

    # List files in most recent release
    RELEASE_FILES_AVAILABLE=$(curl -s -S $URL | grep $FILE_PATTERN)

    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        if [[ "$QUIET" == 1 ]]; then
            return 1
        else
            echo "Error: no release files relating to $FILE_PATTERN could be found."
            echo "This could be due to network issues."
            return 1
        fi
    fi

    for RELEASE_FILE in $RELEASE_FILES_AVAILABLE; do
        if curl -s -S "https://releases.quilibrium.com/$RELEASE_FILE" > "$CEREMONYCLIENT_NODE_DIR/$RELEASE_FILE"; then
            if [[ "$QUIET" == 1 ]]; then
                :
            else
                echo "Downloaded and installed file: $RELEASE_FILE."
            fi
        fi
    done
}

CHECK_FILESIZES_MAKE_EXECUTABLE_func() {
    local FILES_TO_CHECK="$1"

    for FILE in $FILES_TO_CHECK; do
        if [[ "$FILE" =~ ".dgst" ]]; then
            # Check that the .dgst and .sg files are above 100 bytes
            if [[ -n $(find "$FILE" -prune -size +100c) ]]; then
                if [[ "$QUIET" == 1 ]]; then
                    :
                else
                    echo "$FILE downloaded."
                fi
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
                if [[ "$QUIET" == 1 ]]; then
                    :
                else
                    echo "$FILE downloaded and made executable."
                fi
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

CONFIRM_NEW_BINARIES_func() {
    NEW_LATEST_NODE_FILE_INSTALLED_PATH=$(./tools/ceremonyclient_env.sh -latest-version 'node-installed-files-quiet')
    NEW_LATEST_NODE_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_NODE_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)
    NEW_LATEST_QCLIENT_FILE_INSTALLED_PATH=$(./tools/ceremonyclient_env.sh -latest-version 'qclient-installed-files-quiet')
    NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME=$(echo "$NEW_LATEST_QCLIENT_FILE_INSTALLED_PATH" | awk -F'/' '{print $NF}' | xargs)

    NEW_LATEST_NODE_FILES=$(find "$CEREMONYCLIENT_NODE_DIR" -type f -name "$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME*")
    NEW_LATEST_QCLIENT_FILES=$(find "$CEREMONYCLIENT_NODE_DIR" -type f -name "$NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME*")

    if [[ "$NEW_LATEST_NODE_FILE_INSTALLED_FILENAME" == "$LATEST_NODE_RELEASE" ]]; then
        if [[ $(CHECK_FILESIZES_MAKE_EXECUTABLE_func "$NEW_LATEST_NODE_FILES") ]]; then
            return 0
        else
            if [[ "$QUIET" == 1 ]]; then
                return 1
            else
                echo "Error: CHECK_FILESIZES_MAKE_EXECUTABLE_func function failed."
                echo "Manually check the file sizes in $CEREMONYCLIENT_NODE_DIR of the files downloaded below:"
                echo "$NEW_LATEST_NODE_FILES"
                return 1
            fi
        fi
    fi
    if [[ "$NEW_LATEST_QCLIENT_FILE_INSTALLED_FILENAME" == "$LATEST_QCLIENT_RELEASE" ]]; then
        if [[ $(CHECK_FILESIZES_MAKE_EXECUTABLE_func "$NEW_LATEST_QCLIENT_FILES") ]]; then
            return 0
        else
            if [[ "$QUIET" == 1 ]]; then
                return 1
            else
                echo "Error: CHECK_FILESIZES_MAKE_EXECUTABLE_func function failed."
                echo "Manually check the file sizes in $CEREMONYCLIENT_NODE_DIR of the files downloaded below:"
                echo "$NEW_LATEST_QCLIENT_FILES"
                return 1
            fi
        fi
    fi
}



while getopts "xhqf" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        f) DOWNLOAD_AND_CONFIRM_func "$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

FETCH_FILES_func "$1"
CONFIRM_NEW_BINARIES_func

exit 0