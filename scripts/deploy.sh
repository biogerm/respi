#!/bin/bash
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
   fi
done
echo "Please input ppp password:"
read KEY
if [ "$KEY" = "" ]; then
   echo "Empty key"
   exit
fi
echo "Please input DDNS password:"
read DDNS_KEY
if [ "$DDNS_KEY" = "" ]; then
   echo "Empty key"
   exit
fi

# install Locale
sudo locale-gen en_US.UTF-8
sudo locale-gen en en_US en_US.UTF-8
echo "Please choose en_US.UTF-8 as the only option in the following dialog and make it as default in the second dialog. Enter to continue."
read enter
sudo dpkg-reconfigure locales
sudo update-locale LANG=en_US.UTF-8 


# Install Emacs and PPTPD
sudo apt-get -q -y install emacs23 pptpd
cp ../configs/.emacs /home/pi/


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

echo "Install done"
read DONE
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

# Enable report DDNS on startup
CMD="`pwd`/report-ddns.sh >> /home/ubuntu/reportddns.log &"
sudo sed -i "\$i$CMD\n" /etc/rc.local

# Replace keys in the DDNS script
sed -i "s/{PASSWORD}/$DDNS_KEY/g" report-ddns.sh

