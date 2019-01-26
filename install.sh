#!/bin/bash

set -ex

PUBLIC_NIC="eth1"
INTERNAL_NIC="eth0"
INTERNAL_NIC_IP="192.168.1.2"
INTERNAL_NIC_NETMASK="255.255.255.0"
INTERNAL_NETWORK_CIDR="192.168.1.0/24"

SSHD_PORT="45678"
NTOPNG_PORT="55555"

# Just use 8.8.8.8 if you don't have an internal DNS server
NAMESERVERS="8.8.8.8 192.168.1.1"

PI_USER_PASSWORD="bananas999"


########################################
### DON'T MODIFY ANYTHING BELOW HERE ###
########################################

function log {
  set +x
  echo -e "\n$1\n"
  set -x
}

# Lock down the pi account
log "Setting password of user pi to $PI_USER_PASSWORD"
echo "pi:${PI_USER_PASSWORD}" | chpasswd

# Add ntopng repo
log "Configuring ntopng apt repo"
wget http://packages.ntop.org/apt/ntop.key
apt-key add ntop.key
rm -f ntop.key
echo "deb http://apt.ntop.org/stretch_pi armhf/" > /etc/apt/sources.list.d/ntop.list
echo "deb http://apt.ntop.org/stretch_pi all/" >> /etc/apt/sources.list.d/ntop.list

# Install packages
log "Updating packages & installing dependencies"
apt-get update
apt-get upgrade -y
apt-get install -y vim htop ntopng ufw
apt autoremove

# Configure ntopng interface & port
log "Configuring ntopng to bind to port $NTOPNG_PORT on interface $INTERNAL_NIC"
sed -i -e 's/^\s*-w=.*$/-i='"$INTERNAL_NIC"'\n-w='"$NTOPNG_PORT"'\n--community/g' /etc/ntopng.conf

# Configure sshd port
log "Configuring sshd to bind to port $SSHD_PORT"
sed -i -e 's/^\s*#Port.*$/Port '"$SSHD_PORT"'/g' /etc/ssh/sshd_config

# Define network configuration
log "Configuring interfaces $PUBLIC_NIC and $INTERNAL_NIC in /etc/network/interfaces"
cat << EOF >> /etc/network/interfaces
auto lo $PUBLIC_NIC $INTERNAL_NIC

iface lo inet loopback
allow hot-plug $PUBLIC_NIC
iface $PUBLIC_NIC inet dhcp

allow hot-plug $INTERNAL_NIC
iface $INTERNAL_NIC inet static
        address $INTERNAL_NIC_IP
        netmask $INTERNAL_NIC_NETMASK
        dns-nameservers $NAMESERVERS
EOF

# Configure firewall
log "Configuring firewall policies"
ufw default deny incoming
ufw default allow outgoing
ufw allow from $INTERNAL_NETWORK_CIDR
ufw allow $SSHD_PORT
ufw allow from $INTERNAL_NETWORK_CIDR to any port $NTOPNG_PORT

# Enable packet forwarding
log "Modifying /etc/default/ufw and /etc/ufw/sysctl.conf to allow packet forwarding"
sed -i -e 's/^\s*DEFAULT_FORWARD_POLICY.*$/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
sed -i -e 's|^#\s*net/ipv4/ip_forward.*$|net/ipv4/ip_forward=1|g' /etc/ufw/sysctl.conf
sed -i -e 's|^#\s*net/ipv6/conf/default/forwarding.*$|net/ipv6/conf/default/forwarding=1|g' /etc/ufw/sysctl.conf
sed -i -e 's|^#\s*net/ipv6/conf/all/forwarding.*$|net/ipv6/conf/all/forwarding=1|g' /etc/ufw/sysctl.conf

# Configure the NAT table
log "Adding NAT rule to translate traffic from subnet $INTERNAL_NETWORK_CIDR to interface $PUBLIC_NIC"
sed -i -e 's|*filter|*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s '"$INTERNAL_NETWORK_CIDR"' -o '"$PUBLIC_NIC"' -j MASQUERADE\nCOMMIT\n\n*filter|g' /etc/ufw/before.rules

# Disable DHCP
log "Disable DHCP daemomn"
systemctl disable dhcpcd.service
systemctl stop dhcpcd.service

# Restart networking
log "Restarting networking"
/etc/init.d/networking restart

# Cycle the firewall
log "Restarting the firewall (ufw)"
ufw disable
ufw enable

# Ensure services are enabled at boot
log "Configuring ssh, ufw & ntopng to start at boot"
systemctl enable ssh
systemctl enable ntopng
systemctl enable ufw

log "Installation has finished.  You can reboot your system by running 'reboot'"
