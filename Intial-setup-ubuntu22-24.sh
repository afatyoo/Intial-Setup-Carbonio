#!/bin/bash
echo "================================================"
echo "= Initial Setup Carbonio Script for Ubuntu 22/24="
echo "= by: TYO-CHAN                                 ="
echo "================================================"
set -e
sleep 3

# ==== Check Static IP ====
echo
echo "[0/9] Checking network configuration..."
if grep -q "^[[:space:]]*dhcp4:[[:space:]]*true" /etc/netplan/*.yaml 2>/dev/null; then
    echo "❌ Server masih pakai DHCP"
    exit 1
else
    echo "✅ Static IP detected"
fi

sleep 3

# ==== Update system ====
echo
echo "[1/9] Updating system..."
apt update -y && apt upgrade -y

sleep 3

# ==== Configure Locale ====
echo
echo "[2/9] Configuring locale (en_US.UTF-8 for Carbonio | Ubuntu 24)..."

apt install -y locales

# Pastikan locale aktif
if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
fi

# Generate locale
locale-gen

# Set system locale (Ubuntu 24 preferred way)
update-locale LANG=en_US.UTF-8

# Reload environment
export LANG=en_US.UTF-8

echo "✅ Locale configured:"
locale

sleep 3

# ==== Install base packages ====
echo
echo "[3/9] Installing required packages..."
apt install -y dnsmasq chrony net-tools curl vim resolvconf \
perl python3 wget gnupg lsb-release

sleep 3

# ==== Hostname & Hosts ====
echo
echo "[4/9] Configuring hostname & hosts..."
read -p "IP Address server        : " IPADDRESS
read -p "Hostname (contoh: mail) : " HOSTNAME
read -p "Domain (contoh: afatyo.com): " DOMAIN

cp /etc/hosts /etc/hosts.backup
cp /etc/resolv.conf /etc/resolv.conf.backup

systemctl disable --now systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf

cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > /etc/hosts <<EOF
127.0.0.1 localhost
$IPADDRESS $HOSTNAME.$DOMAIN $HOSTNAME
EOF

hostnamectl set-hostname "$HOSTNAME.$DOMAIN"

sleep 3

# ==== DNSMASQ ====
echo
echo "[5/9] Configuring DNS using dnsmasq..."

DNSCONF="/etc/dnsmasq.d/${DOMAIN}.conf"

if [ ! -f /etc/dnsmasq.conf.backup ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
fi

if ! grep -q "^conf-dir=/etc/dnsmasq.d" /etc/dnsmasq.conf; then
    echo "conf-dir=/etc/dnsmasq.d,*.conf" >> /etc/dnsmasq.conf
fi

cat > "$DNSCONF" <<EOF
# DNS records for $DOMAIN

mx-host=$DOMAIN,$HOSTNAME.$DOMAIN,10
host-record=$DOMAIN,$IPADDRESS
host-record=$HOSTNAME.$DOMAIN,$IPADDRESS
EOF

chmod 644 "$DNSCONF"
systemctl enable dnsmasq
systemctl restart dnsmasq

sleep 3

# ==== Time Sync ====
echo
echo "[6/9] Configuring Chrony..."
systemctl disable --now systemd-timesyncd 2>/dev/null || true
systemctl enable --now chrony
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true

sleep 3

# ==== Firewall ====
echo
echo "[7/9] Firewall configuration..."
read -p "Matikan UFW? (y/n): " FW
if [ "$FW" == "y" ]; then
    systemctl disable --now ufw 2>/dev/null || true
    echo "🔥 Firewall dimatikan"
else
    echo "⚠️ Firewall aktif"
fi

sleep 3

# ==== PostgreSQL 16 (OPTIONAL) ====
echo
echo "[8/9] PostgreSQL 16 installation (optional)"
read -p "Install PostgreSQL 16 sekarang? (y/n): " INSTALL_PG

if [ "$INSTALL_PG" == "y" ]; then
    echo "🚀 Installing PostgreSQL 16..."

    echo "deb [signed-by=/usr/share/keyrings/postgres.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor > /usr/share/keyrings/postgres.gpg

    chmod 644 /usr/share/keyrings/postgres.gpg

    apt update -y
    apt install -y postgresql-16 postgresql-client-16

    systemctl enable --now postgresql
    echo "✅ PostgreSQL 16 running"
else
    echo "⏭️ Skip PostgreSQL"
fi

sleep 3

# ==== Zextras Repo ====
echo
echo "[9/9] Setup Zextras repository..."

UBUNTU_CODENAME=$(lsb_release -cs)

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/zextras.gpg] https://repo.zextras.io/release/ubuntu $UBUNTU_CODENAME main" \
> /etc/apt/sources.list.d/zextras.list

wget -qO- "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5dc7680bc4378c471a7fa80f52fd40243e584a21" \
| gpg --dearmor > /usr/share/keyrings/zextras.gpg

chmod 644 /usr/share/keyrings/zextras.gpg
apt update -y

echo
echo "===================================================================="
echo "= SETUP SELESAI                                                     ="
echo "= Hostname : $(hostname)                                           ="
echo "= Domain   : $DOMAIN                                               ="
echo "= DNS      : dnsmasq                                               ="
echo "= PostgreSQL : $(systemctl is-active postgresql 2>/dev/null || echo skipped) ="
echo "= Locale   : $(localectl status | grep "System Locale")           ="
echo "= NEXT     : Install Carbonio                                      ="
echo "===================================================================="
