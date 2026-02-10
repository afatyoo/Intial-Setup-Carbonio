#!/bin/bash
echo "================================================"
echo "= Initial Setup Carbonio Script for RHEL 8/9   ="
echo "= by: TYO-CHAN                                 ="
echo "================================================"
set -e
sleep 3

# ==== Detect RHEL version ====
if [ -f /etc/redhat-release ]; then
    OS="rhel"
    RHEL_VERSION=$(rpm -E %{rhel})
    echo "✅ Detected RHEL $RHEL_VERSION"
else
    echo "❌ This script is only for RHEL 8/9"
    exit 1
fi

# ==== Check Static IP ====
echo
echo "[0/11] Checking network configuration..."
IFACE=$(nmcli -t -f DEVICE,STATE d | grep ":connected" | cut -d: -f1 | head -n1)
BOOTPROTO=$(nmcli -g ipv4.method con show "$IFACE")

if [ "$BOOTPROTO" == "auto" ]; then
    echo "❌ Server masih pakai DHCP"
    exit 1
else
    echo "✅ Static IP detected"
fi

sleep 3

# ==== Update system ====
echo
echo "[1/11] Updating system..."
dnf clean all
dnf update -y

sleep 3

# ==== Enable EPEL & Repos ====
echo
echo "[2/11] Installing EPEL repository..."
if [ "$RHEL_VERSION" -eq 8 ]; then
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms
    subscription-manager repos --enable=rhel-8-for-x86_64-appstream-rpms
    subscription-manager repos --enable=codeready-builder-for-rhel-8-x86_64-rpms
elif [ "$RHEL_VERSION" -eq 9 ]; then
    dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms
    subscription-manager repos --enable=rhel-9-for-x86_64-appstream-rpms
    subscription-manager repos --enable=codeready-builder-for-rhel-9-x86_64-rpms
fi
echo "✅ EPEL enabled"

sleep 3

# ==== Locale Configuration (Carbonio REQUIRED) ====
echo
echo "[3/11] Configuring system locale (en_US.UTF-8)..."

dnf install -y glibc-langpack-en

# Set locale system-wide
localectl set-locale LANG=en_US.UTF-8

# Export for current session (important for installer)
export LANG=en_US.UTF-8

echo "✅ Locale configured:"
echo "LANG=$LANG"
localectl status | grep LANG || true

sleep 3

# ==== Carbonio Repository ====
echo
echo "[4/11] Configuring Carbonio repository..."
cat > /etc/yum.repos.d/zextras.repo <<EOF
[zextras]
name=zextras
baseurl=https://repo.zextras.io/release/rhel$RHEL_VERSION
enabled=1
repo_gpgcheck=1
gpgcheck=0
gpgkey=https://repo.zextras.io/repomd.xml.key
EOF

sleep 3

# ==== Install required packages ====
echo
echo "[5/11] Installing required packages..."
dnf install -y dnsmasq chrony net-tools curl vim perl python3 \
tar unzip bzip2 wget gnupg

sleep 3

# ==== Hostname & Hosts ====
echo
echo "[6/11] Configuring hostname & hosts..."
read -p "IP Address server           : " IPADDRESS
read -p "Hostname (contoh: mail)    : " HOSTNAME
read -p "Domain (contoh: afatyo.com): " DOMAIN

cp /etc/hosts /etc/hosts.backup
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup

cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF

cat > /etc/hosts <<EOF
127.0.0.1 localhost
$IPADDRESS $HOSTNAME.$DOMAIN $HOSTNAME
EOF

hostnamectl set-hostname "$HOSTNAME.$DOMAIN"

sleep 3

# ==== DNSMASQ SETUP ====
echo
echo "[7/11] Configuring DNS using dnsmasq..."

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
systemctl enable --now dnsmasq

echo "✅ dnsmasq configured"

sleep 3

# ==== Time Sync ====
echo
echo "[8/11] Configuring Chrony..."
systemctl disable --now ntpd 2>/dev/null || true
systemctl enable --now chronyd
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true

sleep 3

# ==== Disable SELinux ====
echo
echo "[9/11] Disabling SELinux..."
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi
setenforce 0 || true

sleep 3

# ==== Disable Firewall ====
echo
echo "[10/11] Disabling Firewall..."
systemctl stop firewalld iptables ip6tables 2>/dev/null || true
systemctl disable firewalld iptables ip6tables 2>/dev/null || true

sleep 3

# ==== PostgreSQL 16 ====
echo
echo "[11/11] Installing PostgreSQL 16..."
if [ "$RHEL_VERSION" -eq 8 ]; then
    dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
elif [ "$RHEL_VERSION" -eq 9 ]; then
    dnf -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
fi

dnf -qy module disable postgresql
dnf install -y postgresql16 postgresql16-server

/usr/pgsql-16/bin/postgresql-16-setup initdb
systemctl enable --now postgresql-16

echo
echo "===================================================================="
echo "= SETUP SELESAI                                                     ="
echo "= Hostname   : $(hostname)                                         ="
echo "= Domain     : $DOMAIN                                             ="
echo "= DNS        : dnsmasq (local)                                     ="
echo "= Locale     : $(localectl status | grep LANG)                     ="
echo "= PostgreSQL : 16 (running)                                        ="
echo "= NEXT STEP  : Install Carbonio                                    ="
echo "===================================================================="
