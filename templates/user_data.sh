#!/bin/ash
# alternative dns
echo -e "nameserver 1.1.1.1\nnameserver 1.1.2.2" > /etc/resolv.conf

# install
apk update && apk add wireguard-tools
modprobe wireguard
echo "wireguard" >> /etc/modules

# configure
sysctl -w net.ipv4.ip_forward=1
[ ! -d /opt/wireguard ] && mkdir /opt/wireguard
cd /opt/wireguard
wg genkey | tee server-priv | wg pubkey > server-pub
chmod 600 server-priv
SERVERPRI=$(cat server-priv)
cat <<EOCONF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.0.0.2/24
SaveConfig = true
ListenPort = ${port}
PrivateKey = $${SERVERPRI}
DNS = 1.1.1.1
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;iptables -A FORWARD -o %i -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;iptables -D FORWARD -o %i -j ACCEPT

[Peer]
PublicKey = ${client}
AllowedIPs = 10.0.0.3/32
EOCONF

# start the service
wg-quick up wg0

# enable at boot time
rc-update add local default
cat <<EOCODE > /etc/local.d/wg.start
#!/bin/ash
wg-quick up wg0
EOCODE
chmod +x /etc/local.d/wg.start
