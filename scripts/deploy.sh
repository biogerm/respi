#!/bin/bash
git config --global user.email "biogerm@github.com"
git config --global user.name "BiOgErM"

# Check if the script is executed as sudoer
error() {
  printf '\E[31m'; echo "$@"; printf '\E[0m'
}

if [[ $EUID -ne 0 ]]; then
    error "This script should be run using sudo or as the root user"
    exit 1
fi

# User choices of functions

while [ true ]; do
   echo "Would you like to setup AirPlay? (Y/N)"
   read AIRPLAY_YES
   if [ "$AIRPLAY_YES" = "Y" ]  || [ "$AIRPLAY_YES" = "y" ]; then
      echo "Please name your AirPlay server"
      read AIRPLAYNAME
      if [ "$AIRPLAYNAME" = "" ]; then
        echo "Empty input, try again"
      else
        AIRPLAY="true"
	break
      fi
   elif [ "$AIRPLAY_YES" = "N" ]  || [ "$AIRPLAY_YES" = "n" ]; then
      AIRPLAY="false"
      break
   else
       echo "Please type Y or N"
   fi
done

while [ true ]; do
   echo "Would you like to setup PPTP? (Y/N)"
   read PPTP_YES
   if [ "$PPTP_YES" = "Y" ]  || [ "$PPTP_YES" = "y" ]; then
       echo "Please input ppp password:"
       read KEY
       if [ "$KEY" = "" ]; then
	   echo "Empty password, try again"
       else
	   PPTP="true"
	   break
       fi
   elif [ "$PPTP_YES" = "N" ]  || [ "$PPTP_YES" = "n" ]; then
       PPTP="false"
       break
   else
       echo "Please type Y or N"
   fi
done

while [ true ]; do
    echo "Would you like to setup DDNS? (Y/N)"
    read DDNS_YES
    if [ "$DDNS_YES" = "Y" ]  || [ "$DDNS_YES" = "y" ]; then
	     echo "Please input DDNS password:"
	     read DDNS_KEY
	     if [ "$DDNS_KEY" = "" ]; then
	       echo "Empty password, try again"
	     else
	       DDNS="true"
	       break
	     fi
    elif [ "$DDNS_YES" = "N" ]  || [ "$DDNS_YES" = "n" ]; then
        DDNS="false"
	       break
    else
        echo "Please type Y or N"
    fi
done

while [ true ]; do
    echo "Would you like to setup LIRC Universal Remote Controller (Require tailor made hardware)? (Y/N)"
    read LIRC_YES
    if [ "$LIRC_YES" = "Y" ]  || [ "$LIRC_YES" = "y" ]; then
        LIRC="true"
        echo "Please input LIRC_IN GPIO port number (default 23):"
        read LIRC_IN
        if [ "$LIRC_IN" = "" ]; then
          echo "Empty LIRC_IN, use default 23"
          LIRC_IN=23
        fi
        echo "Please input LIRC_OUT GPIO port number (default 22):"
        read LIRC_OUT
        if [ "$LIRC_OUT" = "" ]; then
          echo "Empty LIRC_OUT, use default 22"
          LIRC_OUT=22
        fi
        break
    elif [ "$LIRC_YES" = "N" ]  || [ "$LIRC_YES" = "n" ]; then
        LIRC="false"
        break
    else
        echo "Please type Y or N"
    fi
done

while [ true ]; do
    echo "Would you like to automatically reboot RPi everyday? (Y/N)"
    read ANSWER
    if [ "$ANSWER" = "Y" ]  || [ "$ANSWER" = "y" ]; then
        crontab -l > mycron
        filename="mycron"
        echo "0 14 * * * reboot" >> mycron
        crontab mycron
        rm mycron
        break
    elif [ "$ANSWER" = "N" ]  || [ "$ANSWER" = "n" ]; then
        break
    else
        echo "Please type Y or N"
    fi
done

# Generic functions
function replaceLine {
  filename=$1
  from=$2
  to=$3
  sudo sed -i "s/${from}/${to}/g" ${filename}
}

function addNewLine {
  filename=$1
  line=$2
  sudo sed -i "\$i${line}\n" ${filename}
}

# install Locale
sudo locale-gen en_US.UTF-8
sudo locale-gen en en_US en_US.UTF-8
echo "Please choose en_US.UTF-8 as the only option in the following dialog and make it as default in the second dialog. Enter to continue."
read enter
sudo dpkg-reconfigure locales
sudo update-locale LANG=en_US.UTF-8 
export LC_ALL "en_US.UTF-8"

# Install Emacs and PPTPD 
sudo apt-get -q -y install emacs23 pptpd
cp ../configs/.emacs /home/pi/
CMD="cp `pwd`/../configs/.emacs /home/pi/"
$CMD

# Install AirPlayer
function installAirPlay {
    echo "Enabling AirPlay"
    sudo apt-get -q -y install git libao-dev libssl-dev libcrypt-openssl-rsa-perl libio-socket-inet6-perl libwww-perl avahi-utils libmodule-build-perl
    echo "Cloning perl-net-sdp repo"
    cd /home/pi/git
    git clone https://github.com/njh/perl-net-sdp.git perl-net-sdp
    echo "Installing perl-net-sdp"
    cd perl-net-sdp
    perl Build.PL
    sudo ./Build
    sudo ./Build test
    sudo ./Build install
    echo "Done installing perl-net-sdp"
    echo "Cloning shairport repo"
    cd /home/pi/git
    git clone https://github.com/hendrikw82/shairport.git
    cd shairport
    sudo make install
    echo "SharePort installed, configuring"
    sudo cp shairport.init.sample /etc/init.d/shairport
    cd /etc/init.d
    sudo chmod a+x shairport
    sudo update-rc.d shairport defaults
    sudo sed -i 's/-w $PIDFILE"/-w $PIDFILE -a '$AIRPLAYNAME'"/' /etc/init.d/shairport
}

if [ "$AIRPLAY" = "true" ]; then
    installAirPlay
fi

# Configure PPTP VPN
function configurePPTP {
    # Enable IPv4 port forwarding
    sudo sed -i -r 's/^\s*#(net\.ipv4\.ip_forward=1.*)/\1/' /etc/sysctl.conf
    # Reload the config file to have the change take effect immediately.
    sudo -i sysctl -p

    OUTIF=`/sbin/ip route show to exact 0/0 | sed -r 's/.*dev\s+(\S+).*/\1/'`
    ##sudo -i iptables --table nat --append POSTROUTING --out-interface $OUTIF --jump MASQUERADE
    # Enable NAT on boot from the rc.local script.
    CMD="iptables --table nat --append POSTROUTING --out-interface $OUTIF --jump MASQUERADE"
    
    sudo -i $CMD
    sudo sed -i "\$i$CMD\n" /etc/rc.local
    
    echo "biogerm pptpd $KEY *" | sudo tee -a /etc/ppp/chap-secrets
    echo "ms-dns 8.8.8.8" | sudo tee -a /etc/ppp/pptpd-options
    echo "ms-dns 8.8.4.4" | sudo tee -a /etc/ppp/pptpd-options
    sudo /etc/init.d/pptpd restart
    echo "PPTP ready"
}

if [ "$PPTP" = "true" ]; then
    configurePPTP
fi

# Configure DDNS
function configureDDNS {
    # Enable report DDNS on startup
    CMD="`pwd`/report-ddns.sh >> /home/pi/reportddns.log &"
    sudo sed -i "\$i$CMD\n" /etc/rc.local

    # Replace keys in the DDNS script
    sed -i "s/{PASSWORD}/$DDNS_KEY/g" report-ddns.sh
}

if [ "$DDNS" = "true" ]; then
    configureDDNS
fi

# Configure LIRC
function configureLIRC {
  sudo apt-get -y install lirc

  # modules
  filename="/etc/modules"
  addNewLine $filename "lirc_dev"
  addNewLine $filename "lirc_rpi gpio_in_pin=$LIRC_IN gpio_out_pin=$LIRC_OUT"

  # hardware.conf
  filename="/etc/lirc/hardware.conf"
  replaceLine $filename 'LIRCD_ARGS=""' 'LIRCD_ARGS="--uinput"'
  replaceLine $filename UNCONFIGURED default
  replaceLine $filename 'DEVICE=""' 'DEVICE="\/dev\/lirc0"'
  replaceLine $filename 'MODULES=""' 'MODULES="lirc_rpi"'

  # boot config
  filename="/boot/config.txt"
  addNewLine $filename "dtoverlay=lirc-rpi,gpio_in_pin=$LIRC_IN,gpio_out_pin=$LIRC_OUT"

  # PowerBot profile
  sudo cp ../configs/samsung_robot_customized.conf /etc/lirc/lircd.conf

  # Start Service
  sudo /etc/init.d/lirc start

  # Crontab
  crontab -l > mycron
  filename="mycron"
  echo "30 11 * * 1-5 /home/pi/git/respi/scripts/robot-control.sh" >> mycron
  crontab -u pi mycron
  rm mycron
} 

if [ "$LIRC" = "true" ]; then
    configureLIRC
fi

# Enable Wifi Auto-reconnect
CMD="`pwd`/network-monitor.sh >> /home/pi/networkMonitor.log &"
sudo sed -i "\$i$CMD\n" /etc/rc.local
