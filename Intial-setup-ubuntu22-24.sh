#!/bin/bash
echo "================================================"
echo "= Initial Setup Carbonio Script for Ubuntu 22/24="
echo "= by: TYO-CHAN                                 ="
echo "================================================"
set -e
sleep 3

# ==== Check Static IP or DHCP ====
echo
echo
echo "[0/7] Checking network configuration..."
if [ -f /etc/redhat-release ]; then
    # RHEL based check
    IFACE=$(nmcli -t -f DEVICE,STATE d | grep ":connected" | cut -d: -f1 | head -n1)
    BOOTPROTO=$(nmcli -g ipv4.method con show $IFACE)
    if [ "$BOOTPROTO" == "auto" ]; then
        echo "❌ Server masih pakai DHCP (dynamic IP)."
        echo "👉 Disarankan ganti ke static IP sebelum lanjut."
        exit 1
    else
        echo "✅ Server sudah pakai static IP."
    fi
elif [ -f /etc/lsb-release ]; then
    # Ubuntu
    if grep -q "^[[:space:]]*dhcp4:[[:space:]]*true" /etc/netplan/*.yaml 2>/dev/null; then
        echo "❌ Server masih pakai DHCP (dynamic IP)."
        echo "👉 Edit /etc/netplan/*.yaml untuk set static IP lalu apply dengan:"
        echo "   sudo netplan apply"
        exit 1
    else
        echo "✅ Server sudah pakai static IP."
    fi
elif [ -f /etc/debian_version ]; then
    # Debian
    if grep -q "^[[:space:]]*dhcp4:[[:space:]]*true" /etc/netplan/*.yaml 2>/dev/null; then
        echo "❌ Server masih pakai DHCP (dynamic IP)."
        echo "👉 Edit /etc/netplan/*.yaml untuk set static IP lalu apply dengan:"
        echo "   sudo netplan apply"
        exit 1
    else
        echo "✅ Server sudah pakai static IP."
    fi
else
    echo "Unsupported OS"
    exit 1
fi

sleep 3
# ==== Update system ====
echo
echo
echo "[1/7] Updating system..."
if [ -f /etc/redhat-release ]; then
    sudo dnf update -y
    sudo dnf install -y epel-release
    PKG="dnf"
    OS="rhel"
elif [ -f /etc/lsb-release ]; then
    sudo apt update -y
    sudo apt upgrade -y
    PKG="apt"
    OS="ubuntu"
elif [ -f /etc/debian_version ]; then
    sudo apt update -y
    sudo apt upgrade -y
    PKG="apt"
    OS="debian"
else
    echo "Unsupported OS"
    exit 1
fi

sleep 3
# ==== Install required packages ====
echo
echo
echo "[2/7] Installing required packages..."
if [ "$OS" == "rhel" ]; then
    sudo $PKG install -y dnsmasq chrony net-tools curl vim perl python3
else
    sudo $PKG install -y dnsmasq chrony net-tools curl vim resolvconf perl python3 wget gnupg lsb-release
fi

sleep 3
# ==== Setup /etc/hosts & hostname ====
echo
echo
echo "[3/7] Configuring /etc/hosts and hostname..."
read -p "Masukkan IP Address server: " IPADDRESS
read -p "Masukkan Hostname server: " HOSTNAME
read -p "Masukkan Domain server: " DOMAIN

# Backup resolv.conf & hosts
cp /etc/resolv.conf /etc/resolv.conf.backup
cp /etc/hosts /etc/hosts.backup

# ==== Disable systemd-resolved (Ubuntu/Debian only) ====
if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
    echo "Menonaktifkan systemd-resolved..."
    systemctl disable --now systemd-resolved 2>/dev/null || true
    rm -f /etc/resolv.conf
    touch /etc/resolv.conf
fi

# Insert localhost sebagai resolver pertama
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF


# Tulis ulang hosts
echo "127.0.0.1       localhost" > /etc/hosts
echo "$IPADDRESS   $HOSTNAME.$DOMAIN       $HOSTNAME" >> /etc/hosts

# Set hostname
hostnamectl set-hostname $HOSTNAME.$DOMAIN

sleep 3
# ==== Setup chrony ====
echo
echo
echo "[4/7] Configuring Chrony..."
if [ "$OS" == "rhel" ]; then
    systemctl disable --now ntpd 2>/dev/null || true
    systemctl enable --now chronyd
else
    systemctl disable --now systemd-timesyncd 2>/dev/null || true
    systemctl enable --now chrony
fi

# Set timezone ke Asia/Jakarta
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true

sleep 3
# ==== Disable Firewall (optional) ====
echo
echo
echo "[5/7] Firewall configuration..."
read -p "Matikan firewall sekarang? (y/n): " FWCHOICE
if [ "$FWCHOICE" == "y" ]; then
    if [ "$OS" == "rhel" ]; then
        systemctl disable --now firewalld 2>/dev/null || true
        echo "🔥 Firewalld sudah dimatikan."
    else
        systemctl disable --now ufw 2>/dev/null || true
        echo "🔥 UFW sudah dimatikan."
    fi
else
    echo "⚠️ Firewall tetap aktif, pastikan port untuk Carbonio dibuka manual."
fi

sleep 3
# ==== Install PostgreSQL 16 ====
echo
echo
echo
echo
echo "[6/7] PostgreSQL 16 installation (optional)..."
read -p "Apakah ingin menginstal PostgreSQL 16 (untuk LDAP)? (y/n): " INSTALL_PG

if [ "$INSTALL_PG" == "y" ]; then
    echo "🚀 Memulai instalasi PostgreSQL 16..."
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        # Tambah repo PostgreSQL
        echo "deb [signed-by=/usr/share/keyrings/postgres.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list

        # Download GPG key PostgreSQL
        wget -qO- "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | \
        gpg --dearmor | sudo tee /usr/share/keyrings/postgres.gpg >/dev/null
        chmod 644 /usr/share/keyrings/postgres.gpg

        # Update dan install PostgreSQL 16
        sudo apt update -y
        sudo apt install -y postgresql-16 postgresql-client-16
        systemctl enable --now postgresql
        echo "✅ PostgreSQL 16 terinstall & berjalan."
    elif [ "$OS" == "rhel" ]; then
        dnf install -y https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        dnf install -y postgresql16 postgresql16-server
        /usr/pgsql-16/bin/postgresql-16-setup initdb
        systemctl enable --now postgresql-16
        echo "✅ PostgreSQL 16 terinstall & berjalan."
    fi
else
    echo "⏭️  Melewati instalasi PostgreSQL 16."
fi

sleep 3
# ==== Setup Zextras Repo ====
echo
echo
echo "[7/7] Setup Zextras Repo..."
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/zextras.gpg] https://repo.zextras.io/release/ubuntu jammy main" > /etc/apt/sources.list.d/zextras.list
wget -qO- "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5dc7680bc4378c471a7fa80f52fd40243e584a21" | gpg --dearmor | sudo tee /usr/share/keyrings/zextras.gpg >/dev/null
chmod 644 /usr/share/keyrings/zextras.gpg

sleep 3
echo
echo
echo "===================================================================="
echo "= Setup selesai! Detail:                                           "
echo "= - Hostname  : $(hostname)                                        "
echo "= - Domain    : $DOMAIN                                            "
echo "= - PostgreSQL: version 16 (running)                               "
echo "= - Catatan   : DNS server belum di setup silahkan di setup manual "
echo "===================================================================="
