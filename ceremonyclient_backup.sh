#!/bin/bash

# Set shell options
set -eou pipefail
#set -x    # for debugging purposes - this prints the command that is to be executed before the command is executed

USAGE_func() {
    echo ""
    echo "Backup tool for the Quilibrium node."
    echo ""
    echo "USAGE: bash ceremonyclient_backup.sh [-h] [-x] [-c]"
    echo ""
    echo "       -h    Display this help dialogue."
    echo "       -x    For debugging the script; sets the x shell builtin, 'set -x'."
    echo "       -c    (Optional) This node is part of a cluster."
    echo "             (By default this is set to null, meaning this node is run as a standalone node.)"
    echo "       -d    (Optional) Directory to update binaries in."
    echo "             By default, the directory to install to is determined by the 'ceremonyclient_node_dir' key in .localenv."
    echo ""
    exit 0
}
dateAndTime=$(date +%y%m%d-%H:%M:%S)
#node=`find /root/ceremonyclient/node -maxdepth 1 -type f -executable -name 'node-*-linux-amd64' -ls | head -1 | awk '{print $NF}'`
#peerID=`$node -peer-id | grep -oP '^Peer ID: \K\w+'`

echo $dateAndTime > /root/ceremonyclient_backup/updates-rsync.txt
printf "\n" >> /root/ceremonyclient_backup/updates-rsync.txt

rsync -avhp /root/ceremonyclient/node/.config /root/ceremonyclient_backup/node/.config >> /root/ceremonyclient_backup/updates-rsync.txt
tar -czf /root/ceremonyclient_backup.tar.gz /root/ceremonyclient_backup

rclone copy /root/ceremonyclient_backup.tar.gz rhquil2:$USER/node1

exit 0