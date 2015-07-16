#!/bin/bash
while true ; do
IP="$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//')"
echo "${IP}"
ssh -o ConnectTimeout=10 -i /home/pi/git/respi/scripts/ubuntuFree.pem ubuntu@50.18.192.139 bash -c "'echo `date +%Y%m%d' '%H:%M:%S` $IP >> /home/ubuntu/homeIp'"
echo "sent"
sleep 600
done
