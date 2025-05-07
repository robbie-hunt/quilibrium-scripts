#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Backup tool for backing up the Quilibrium node .config directory (minus the store) to a remote directory."
    echo ""
    echo "USAGE: bash ceremonyclient_backup.sh [-h] [-x] [-r remote destination]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -r    Name of the rclone destination you want to send the backup to."
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
SCRIPT_PARENT_DIR=$(echo "$SCRIPT_DIR" | awk -F'/' 'BEGIN{OFS=FS} {$NF=""; print}' | sed 's/\/*$//')

TIMESTAMP=$(date +%y%m%d-%H:%M:%S)

HOSTNAME=$(hostname)

PEER_ID=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "peer_id")
CEREMONYCLIENT_ROOT_DIR=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_root_dir")
CEREMONYCLIENT_CONFIG_DIR=$(bash $SCRIPT_DIR/tools/ceremonyclient_env.sh -key "ceremonyclient_config_dir")

BACKUP_PARENT_DIR=$(dirname "$CEREMONYCLIENT_ROOT_DIR")
BACKUP_DIR=$(echo "$BACKUP_PARENT_DIR/ceremonyclient_backup")
BACKUP_ZIP="$BACKUP_DIR"_"$PEER_ID"_"$HOSTNAME"
RSYNC_LOGFILE="$BACKUP_DIR/rsync_$TIMESTAMP.log"

REMOTE_NAME=""

while getopts "xhr:" opt; do
    case "$opt" in
        x) set -x;;
        h) USAGE_func; exit 0;;
        r) REMOTE_NAME="$OPTARG";;
        *) USAGE_func; exit 0;;
    esac
done

if [[ -z "$PEER_ID" ]]; then
    echo "ceremonyclient_backup.sh error [$(date)]: .localenv has no value for the peer_id key."
    exit 1
fi

if [[ -z "$CEREMONYCLIENT_ROOT_DIR" ]]; then
    echo "ceremonyclient_backup.sh error [$(date)]: .localenv has no value for the ceremonyclient_root_dir key."
    exit 1
fi

if [[ -z "$CEREMONYCLIENT_CONFIG_DIR" ]]; then
    echo "ceremonyclient_backup.sh error [$(date)]: .localenv has no value for the ceremonyclient_config_dir key."
    exit 1
fi

# Make sure the remote destination supplied is correct
if [[ "$REMOTE_NAME" == "" ]]; then
    echo "ceremonyclient_backup.sh error [$(date)]: Please supply a remote destination using -r."
    exit 1
fi
if rclone ls "$REMOTE_NAME:" > /dev/null 2>&1; then
    REMOTE_DESTINATION="$REMOTE_NAME:Quilibrium"
else
    echo "ceremonyclient_backup.sh error [$(date)]: rclone couldn't connect to '$REMOTE_NAME'. Please debug this yourself. Exiting..."
    exit 1
fi
RCLONE_PARENT_DIR="$REMOTE_DESTINATION/$PEER_ID/$HOSTNAME"

# Create backup dir if it doesn't exist
if [[ -d "$BACKUP_DIR" ]]; then
    :
else
    mkdir "$BACKUP_DIR"
fi

# Reset rsync logfile
if ls $BACKUP_DIR/rsync_* > /dev/null 2>&1; then
    rm -r $BACKUP_DIR/rsync_*
fi
echo $TIMESTAMP > "$RSYNC_LOGFILE"
printf "\n" >> "$RSYNC_LOGFILE"

# rsync - copy over config files, excluding store folder
if rsync -avhpR -n --exclude "store" "$CEREMONYCLIENT_CONFIG_DIR" "$BACKUP_DIR" &>/dev/null; then
    rsync -avhpR --exclude "store" "$CEREMONYCLIENT_CONFIG_DIR" "$BACKUP_DIR" >> "$RSYNC_LOGFILE"
else
    echo "ceremonyclient_backup.sh error [$(date)]: rsync command 'rsync -avhpR -n --exclude store $CEREMONYCLIENT_CONFIG_DIR $BACKUP_DIR' failed. Exiting..."
    exit 1
fi

# Zip backup dir
zip -rFSX "$BACKUP_ZIP".zip "$BACKUP_DIR"

# rclone - copy zipped backup dir to Dropbox
if rclone -n copy "$BACKUP_ZIP".zip "$RCLONE_PARENT_DIR" &>/dev/null; then
    rclone copy "$BACKUP_ZIP".zip "$RCLONE_PARENT_DIR"
else
    echo "ceremonyclient_backup.sh error [$(date)]: rclone command 'rclone -n copy "$BACKUP_ZIP" "$RCLONE_PARENT_DIR"' failed. Exiting..."
    exit 1
fi

exit