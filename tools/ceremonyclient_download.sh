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
    echo ""
    exit 0
}

QUIET=0

CEREMONYCLIENT_NODE_DIR=$(./ceremonyclient_env.sh -key "ceremonyclient_node_dir")

FETCH_FILES_func() {
    RELEASE_FILES_AVAILABLE=$(curl -s -S "$URL" | grep "$FILE_PATTERN" || true)

    if [[ -z "$RELEASE_FILES_AVAILABLE" ]]; then
        if [[ "$QUIET" == 1 ]]; then
            return 1
        else
            echo "Error: no release files relating to $FILE_PATTERN could be found."
            echo "This could be due to network issues, a bad spelling provided to -f, or trouble connecting to $URL."
            return 1
        fi
    fi

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

DOWNLOAD_AND_CONFIRM_func() {
    FETCH_FILES_func "$1"
    CONFIRM_NEW_BINARIES_func
}



while getopts "xhqf:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        f) FILE_PATTERN="$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

TYPE=$(echo "$FILE_PATTERN" | awk -F'-' '{print $1}')
TYPE_AS_KEY=$(echo $TYPE"_release_url")
URL=$(./ceremonyclient_env.sh -key "$TYPE_AS_KEY")

LATEST_VERSION_INSTALLED=$(./ceremonyclient_env.sh -latest-version "$TYPE-installed-files-quiet")
LATEST_VERSION_RELEASED=$(./ceremonyclient_env.sh -latest-version "$TYPE-release-files-quiet")

DOWNLOAD_AND_CONFIRM_func "$FILE_PATTERN"

exit 0