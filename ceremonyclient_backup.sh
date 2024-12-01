#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

user="Robbie"

dateAndTime=`date +%y%m%d-%H:%M:%S`
#node=`find /root/ceremonyclient/node -maxdepth 1 -type f -executable -name 'node-*-linux-amd64' -ls | head -1 | awk '{print $NF}'`
#peerID=`$node -peer-id | grep -oP '^Peer ID: \K\w+'`

echo $dateAndTime > /root/ceremonyclient_backup/updates-rsync.txt
printf "\n" >> /root/ceremonyclient_backup/updates-rsync.txt

rsync -avhp /root/ceremonyclient/node/.config /root/ceremonyclient_backup/node/.config >> /root/ceremonyclient_backup/updates-rsync.txt
tar -czf /root/ceremonyclient_backup.tar.gz /root/ceremonyclient_backup

rclone copy /root/ceremonyclient_backup.tar.gz rhquil2:$user/node1

exit 0