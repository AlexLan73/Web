#!/bin/bash
# install.sh — шлюз на ПК1: NAT + DHCP/DNS для ПК2.
# Запуск от root из этого каталога:  WAN=usb0 LAN=enp3s0 ./install.sh
set -euo pipefail

WAN="${WAN:-usb0}"
LAN="${LAN:-enp3s0}"
LAN_ADDR="${LAN_ADDR:-10.10.0.1/24}"
HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '\033[1;34m[pc1]\033[0m %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "нужен root" >&2; exit 1; }

ip link show "$WAN" >/dev/null 2>&1 || { echo "нет интерфейса $WAN (см. ip -br link)" >&2; exit 1; }
ip link show "$LAN" >/dev/null 2>&1 || { echo "нет интерфейса $LAN (см. ip -br link)" >&2; exit 1; }

# --- адрес на LAN ---------------------------------------------------------
if ! ip -4 addr show "$LAN" | grep -q "${LAN_ADDR%/*}"; then
  log "назначаю $LAN_ADDR на $LAN"
  ip addr add "$LAN_ADDR" dev "$LAN"
fi
ip link set "$LAN" up

# --- форвардинг -----------------------------------------------------------
log "ip_forward"
cat > /etc/sysctl.d/90-session-gateway.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=0
EOF
sysctl --system >/dev/null

# --- nftables -------------------------------------------------------------
command -v nft >/dev/null 2>&1 || { log "ставлю nftables"; apt-get update -qq && apt-get install -y nftables; }

log "правила: WAN=$WAN LAN=$LAN LANNET=${LAN_ADDR%.*}.0/24"
# /etc/nftables.conf перезаписывается целиком — прежний сохраняем один раз
[ -e /etc/nftables.conf ] && [ ! -e /etc/nftables.conf.pre-session ] \
  && cp -a /etc/nftables.conf /etc/nftables.conf.pre-session && log "старый: /etc/nftables.conf.pre-session"
sed -e "s|define WAN     = \"usb0\"|define WAN     = \"$WAN\"|" \
    -e "s|define LAN     = \"enp3s0\"|define LAN     = \"$LAN\"|" \
    -e "s|define LANNET  = \"10.10.0.0/24\"|define LANNET  = \"${LAN_ADDR%.*}.0/24\"|" \
    "$HERE/gateway.nft" > /etc/nftables.conf

nft -f /etc/nftables.conf
systemctl enable nftables >/dev/null 2>&1 || true

# --- dnsmasq --------------------------------------------------------------
command -v dnsmasq >/dev/null 2>&1 || { log "ставлю dnsmasq"; apt-get install -y dnsmasq; }
sed -e "s|^interface=enp3s0|interface=$LAN|" \
    -e "s|option:router,10.10.0.1|option:router,${LAN_ADDR%/*}|" \
    -e "s|option:dns-server,10.10.0.1|option:dns-server,${LAN_ADDR%/*}|" \
    -e "s|^dhcp-range=.*|dhcp-range=${LAN_ADDR%.*}.50,${LAN_ADDR%.*}.60,255.255.255.0,12h|" \
    "$HERE/dnsmasq-session.conf" > /etc/dnsmasq.d/session.conf
systemctl restart dnsmasq

log "готово"
echo "--- проверка ---"
nft list table ip session_nat | grep -E 'masquerade' || echo "НЕТ правила masquerade"
systemctl is-active dnsmasq
ip -4 addr show "$LAN" | grep inet
echo
echo "На ПК2 шлюз и DNS должны быть ${LAN_ADDR%/*}."
echo "Проверка с ПК2:  ip route; curl -sI https://github.com | head -1"
