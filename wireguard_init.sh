#!/bin/bash
CLIENTPUB=$1

# deal with Ubuntu/AWS dns
systemctl disable systemd-resolved.service ; service systemd-resolved stop
echo -e "nameserver 1.1.1.1\nnameserver 1.1.2.2" > /etc/resolv.conf

# configure
sysctl -w net.ipv4.ip_forward=1
mkdir /opt/wireguard ; cd /opt/wireguard
wg genkey | tee server-priv | wg pubkey > server-pub
chmod 600 server-priv
SERVERPRI=$(cat server-priv)
cat <<EOCONF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.0.0.2/24
SaveConfig = true
ListenPort = 51820
PrivateKey = ${SERVERPRI}
DNS = 1.1.1.1
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = ${CLIENTPUB}
AllowedIPs = 10.0.0.3/32
EOCONF

echo "Server's peer config for clients:"
cat <<EOCLIENTCONF
[Peer]
PublicKey = $(cat server-pub)
Endpoint = $(curl ifconfig.io/ip):51820
AllowedIPs = 0.0.0.0/0, ::/0
EOCLIENTCONF

# enable and start the service
systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service
