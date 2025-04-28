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
RCLONE_PARENT_DIR="rhquil2:Quilibrium"






echo $TIMESTAMP > /root/ceremonyclient_backup/updates-rsync.txt
printf "\n" >> /root/ceremonyclient_backup/updates-rsync.txt

rsync -avhp /root/ceremonyclient/node/.config /root/ceremonyclient_backup/node/.config >> /root/ceremonyclient_backup/updates-rsync.txt
tar -czf /root/ceremonyclient_backup.tar.gz /root/ceremonyclient_backup

rclone copy /root/ceremonyclient_backup.tar.gz rhquil2:$USER/node1

exit 0