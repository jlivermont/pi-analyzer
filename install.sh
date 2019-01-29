#!/bin/bash

set -ex

PUBLIC_NIC="eth1"
INTERNAL_NIC="eth0"
INTERNAL_NIC_IP="192.168.1.1"
INTERNAL_NIC_NETMASK="255.255.255.0"
INTERNAL_NETWORK_CIDR="192.168.1.0/24"

SSHD_PORT="33333"
NTOPNG_PORT="44444"
PIHOLE_PORT="55555"

PI_USER_PASSWORD="bananas999"
PIHOLE_WEB_ADMIN_PASSWORD="admin"

##########################################################
### IT'S UNUSUAL TO NEED TO MODIFY ANYTHING BELOW HERE ###
##########################################################

NTOPNG_CONF_FILE="/etc/ntopng/ntopng.conf"

PIHOLE_URL="https://install.pi-hole.net"
PIHOLE_CONF_DIR="/etc/pihole"
PIHOLE_CONF_FILE="${PIHOLE_CONF_DIR}/setupVars.conf"
PIHOLE_DNS_PORT="53"

HOSTNAME="pi-firewall"
NAMESERVERS="8.8.8.8 208.67.222.222 192.168.1.1"
DHCP_RANGE_START="192.168.1.100"
DHCP_RANGE_END="192.168.1.251"

########################################
### DON'T MODIFY ANYTHING BELOW HERE ###
########################################

function log {
  set +x
  echo -e "\n$1\n"
  set -x
}

# Lock down the pi account
function set_pi_user_password {
  log "Setting password of user pi to $PI_USER_PASSWORD"
  echo "pi:${PI_USER_PASSWORD}" | chpasswd
}

# Add ntopng repo
function add_ntopng_repo {
  log "Configuring ntopng apt repo"
  wget http://packages.ntop.org/apt/ntop.key
  apt-key add ntop.key
  rm -f ntop.key
  echo "deb http://apt.ntop.org/stretch_pi armhf/" > /etc/apt/sources.list.d/ntop.list
  echo "deb http://apt.ntop.org/stretch_pi all/" >> /etc/apt/sources.list.d/ntop.list
}

# Install packages
function add_and_update_packages {
  log "Updating packages & installing dependencies"
  apt-get update
  apt-get upgrade -y
  apt-get install -y vim htop ntopng ufw
  apt autoremove
}

# Configure network & servics
function configure_network_and_services {
  # Set the hostname
  hostnamectl set-hostname $HOSTNAME
  echo "$INTERNAL_NIC_IP $HOSTNAME" >> /etc/hosts

  # Configure ntopng interface & port
  log "Configuring ntopng to bind to port $NTOPNG_PORT on interface $INTERNAL_NIC"
  echo "-i=$INTERNAL_NIC" >> $NTOPNG_CONF_FILE
  echo "-W=$NTOPNG_PORT" >> $NTOPNG_CONF_FILE
  echo "--commmunity" >> $NTOPNG_CONF_FILE

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

  # Disable DHCP
  log "Disabling DHCP daemomn"
  systemctl disable dhcpcd.service
  systemctl stop dhcpcd.service
}

# Configure firewall
function configure_firewall {
  log "Configuring firewall policies"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from $INTERNAL_NETWORK_CIDR
  ufw allow $SSHD_PORT
  ufw allow from $INTERNAL_NETWORK_CIDR to any port $NTOPNG_PORT
  ufw allow from $INTERNAL_NETWORK_CIDR to any port $PIHOLE_PORT
  ufw allow from $INTERNAL_NETWORK_CIDR to any port $PIHOLE_DNS_PORT

  # Enable packet forwarding
  log "Modifying /etc/default/ufw and /etc/ufw/sysctl.conf to allow packet forwarding"
  sed -i -e 's/^\s*DEFAULT_FORWARD_POLICY.*$/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw
  sed -i -e 's|^#\s*net/ipv4/ip_forward.*$|net/ipv4/ip_forward=1|g' /etc/ufw/sysctl.conf
  sed -i -e 's|^#\s*net/ipv6/conf/default/forwarding.*$|net/ipv6/conf/default/forwarding=1|g' /etc/ufw/sysctl.conf
  sed -i -e 's|^#\s*net/ipv6/conf/all/forwarding.*$|net/ipv6/conf/all/forwarding=1|g' /etc/ufw/sysctl.conf

  # Configure the NAT table
  log "Adding NAT rule to translate traffic from subnet $INTERNAL_NETWORK_CIDR to interface $PUBLIC_NIC"
  sed -i -e 's|*filter|*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s '"$INTERNAL_NETWORK_CIDR"' -o '"$PUBLIC_NIC"' -j MASQUERADE\nCOMMIT\n\n*filter|g' /etc/ufw/before.rules
}

# Cycle network and services to pick up config changes
function restart_networking_and_services {
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
}

function install_pihole {
  # Define pihole configuration
  log "Configuring pihole install configuration file $PIHOLE_CONF_FILE"
  mkdir -p $PIHOLE_CONF_DIR
cat << EOF >> $PIHOLE_CONF_FILE
PIHOLE_INTERFACE=$INTERNAL_NIC
IPV4_ADDRESS=$INTERNAL_NIC_IP
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
BLOCKING_ENABLED=true
WEBPASSWORD=998ed4d621742d0c2d85ed84173db569afa194d4597686cae947324aa58ab4bb
DNSMASQ_LISTENING=single
PIHOLE_DNS_1=8.8.8.8
PIHOLE_DNS_2=8.8.4.4
PIHOLE_DNS_3=208.67.222.222
PIHOLE_DNS_4=208.67.220.220
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSSEC=true
CONDITIONAL_FORWARDING=false
DHCP_ACTIVE=true
DHCP_START=$DHCP_RANGE_START
DHCP_END=$DHCP_RANGE_END
DHCP_ROUTER=$INTERNAL_NIC_IP
DHCP_LEASETIME=12
PIHOLE_DOMAIN=livtech.local
DHCP_IPv6=true
EOF

  # Install pihole
  log "Installing pihole"
  curl -L $PIHOLE_URL | bash /dev/stdin --unattended
  pihole -g
  pihole -a -p $PIHOLE_WEB_ADMIN_PASSWORD
  sed -i -e "s/= 80/= $PIHOLE_URL/g" /etc/lighttpd/lighttpd.conf
}

# main script
set_pi_user_password
add_ntopng_repo
add_and_update_packages
configure_network_and_services
configure_firewall
restart_networking_and_services
install_pihole

set +x
echo -e "\nssh server port: $SSHD_PORT (exposed on both $INTERNAL_NIC & $PUBLIC_NIC)"
echo "ntopng web admin portal: https://$INTERNAL_NIC_IP:$NTOPNG_PORT (exposed only on $INTERNAL_NIC)"
echo "pihole web admin portal: http://$INTERNAL_NIC_IP:/admin (exposed only on $INTERNAL_NIC)"

echo -e "\nYou can check on the status of the UFW firewall by running: ufw status"
echo "You can check on the status of ntopng by running: systemctl status ntopng"
echo "You can check on the status of pihole by running: pihole status"

echo -e "\nInstallation has finished.  You can reboot your system by running 'reboot'."
