#!/bin/bash
while true ; do
echo "Fetching IP"
IP="$(curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//')"
echo "${IP}"
#ssh -o ConnectTimeout=10 -i /home/pi/git/respi/scripts/trainingpair.pem ubuntu@biogerm.no-ip.org bash -c "'echo `date +%Y%m%d' '%H:%M:%S` {DDNS_DOMAIN} $IP >> /home/ubuntu/homeIp'"
echo "IP address is recored on AWS"
echo "Updating no-ip.org"
curl -X GET "http://{DDNS_USER}:{PASSWORD}@dynupdate.no-ip.com/nic/update?hostname={DDNS_DOMAIN}&myip="${IP}
sleep 600
done
