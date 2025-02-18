#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Tool to check the contents of the .localenv file. Used as a precursor to other scripts that rely on this file."
    echo ""
    echo "USAGE: bash ceremonyclient_check_localenv.sh [-h] [-x] [-q]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -q    Quiet mode."
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

# .localenv file location
LOCALENV="$SCRIPT_ROOT_DIR/.localenv"

CHECK_EXISTENCE_OF_LOCALENV_FILE_func() {
    if [[ -f "$LOCALENV" ]]; then
        :
    else
        if [[ "$QUIET" == 1 ]]; then
            :
        else
            echo "Error: $LOCALENV does not exist."
            echo "Use \`ceremonyclient_env.sh -env-init\` in the tools directory to initialise the $LOCALENV file,"
            echo "and then fill in the missing values."
        fi
        return 1
    fi
    return 0
}

CHECK_LOCAL_ENV_KEYS_VALUES_func() {
    LOCALENV_CONTENTS=$(cat $LOCALENV)
    EMPTY_KEYS=""

    for LINE in $LOCALENV_CONTENTS; do
        KEY=$(echo $LINE | awk -F'=' '{print $1}')
        VALUE=$(echo $LINE | awk -F'=' '{print $2}')

        if [[ "$KEY" == "peer_id" ]]; then
            :
        else
            if [[ -z "$VALUE" ]]; then
                EMPTY_KEYS+=$'\n'"$KEY"
            else
                :
            fi
        fi
    done

    if [[ -z $EMPTY_KEYS ]]; then
        :
    else
        if [[ "$QUIET" == 1 ]]; then
            :
        else
            echo "Error: the keys below contain empty values and need filling in: $EMPTY_KEYS"
        fi
        return 1
    fi

    if [[ "$QUIET" == 1 ]]; then
        :
    else
        echo "$LOCALENV file checked successfully."
    fi
    return 0
}

# Set to 1 by using the -q flag; quietens unnecessary output
QUIET=0

while getopts "xhq" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        q) QUIET=1;;
        *) USAGE_func; exit 0;;
    esac
done
shift $((OPTIND -1))

if CHECK_EXISTENCE_OF_LOCALENV_FILE_func; then
    :
fi

exit