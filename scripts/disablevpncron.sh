#!/bin/bash
source ~/.profile
LAST_LINE=$(tail -n 1 /home/pi/cronlog/`date "+%Y%m%d"`.log)
#echo $LAST_LINE
if [[ $LAST_LINE == *"Success"* ]]; then
    echo "Already enabled, skip."
else
    /home/pi/git/respi/scripts/milogin.py 192.168.0.1 $ROUTER_PASSWORD disable >> /home/pi/cronlog/`date "+%Y%m%d"`.log 2>&1
fi

