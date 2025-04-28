#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Backup tool for the Quilibrium node."
    echo ""
    echo "USAGE: bash ceremonyclient_backup.sh [-h] [-x]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
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
RSYNC_LOGFILE="$BACKUP_DIR/rsync_$TIMESTAMP.log"
RCLONE_PARENT_DIR="rhquil2:Quilibrium/$PEER_ID/$HOSTNAME"

# Check if backup dir exists
    # If yes, continue
    # If no, make it
# Copy config files to folder via rsync, direct rsync log into file which has filename of rsync_timestamp.log
# Zip folder
# Rclone folder to rhquil2, direct log to rclone_timestamp.log

# Create backup dir if it doesn't exist
if [[ -d "$BACKUP_DIR" ]]; then
    :
else
    mkdir "$BACKUP_DIR"
fi

# Reset rsync logfile
echo $TIMESTAMP > "$RSYNC_LOGFILE"
printf "\n" >> "$RSYNC_LOGFILE"

# rsync - copy over config files, excluding store folder
if rsync -avhpR -n --exclude "store" "$CEREMONYCLIENT_CONFIG_DIR" "$BACKUP_DIR" &>/dev/null; then
    rsync -avhpR --exclude "store" "$CEREMONYCLIENT_CONFIG_DIR" "$BACKUP_DIR" >> "$RSYNC_LOGFILE"
else
    echo "ceremonyclient_backup.sh error [$(date)]: rsync command 'rsync -avhpR -n --exclude store $CEREMONYCLIENT_CONFIG_DIR $BACKUP_DIR' failed. Exiting..."
    exit
fi

# Zip backup dir
zip -X $BACKUP_DIR $BACKUP_DIR

# rclone - copy zipped backup dir to Dropbox
if rclone -n copy "$BACKUP_DIR".zip "$RCLONE_PARENT_DIR" &>/dev/null; then
    rclone -n copy "$BACKUP_DIR".zip "$RCLONE_PARENT_DIR"
else
    echo "ceremonyclient_backup.sh error [$(date)]: rclone command 'rclone -n copy "$BACKUP_DIR".zip "$RCLONE_PARENT_DIR"' failed. Exiting..."
    exit
fi

exit




echo $TIMESTAMP > /root/ceremonyclient_backup/updates-rsync.txt
printf "\n" >> /root/ceremonyclient_backup/updates-rsync.txt

rsync -avhp /root/ceremonyclient/node/.config /root/ceremonyclient_backup/node/.config >> /root/ceremonyclient_backup/updates-rsync.txt
tar -czf /root/ceremonyclient_backup.tar.gz /root/ceremonyclient_backup

rclone copy /root/ceremonyclient_backup.tar.gz rhquil2:$USER/node1

exit