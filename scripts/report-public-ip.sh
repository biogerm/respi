#!/bin/bash
while true ; do
echo "Fetching IP"
IP="$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//')"
echo "${IP}"
ssh -o ConnectTimeout=10 -i /home/pi/git/respi/scripts/ubuntuFree.pem ubuntu@50.18.192.139 bash -c "'echo `date +%Y%m%d' '%H:%M:%S` $IP >> /home/ubuntu/homeIp'"
echo "IP address is recored on AWS"
echo "Updating no-ip.org"
curl -X GET "http://biogerm:{PASSWORD}@dynupdate.no-ip.com/nic/update?hostname=biogerm.no-ip.org&myip="${IP}
sleep 600
done
