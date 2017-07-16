#!/bin/bash

while true ; do
   if ifconfig wlan0 | grep -q "inet addr:" ; then
      sleep 60
   else
      echo `date +%Y%m%d' '%H:%M:%S`" Network connection down! Attempting reconnection."
      ifup --force wlan0
      sleep 10
   fi
done
