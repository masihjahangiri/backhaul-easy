#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

# ASCII Art Logo
LOGO="
${MAGENTA}██████╗  █████╗  ██████╗██╗  ██╗██╗  ██╗ █████╗ ██╗   ██╗██╗     
${MAGENTA}██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║  ██║██╔══██╗██║   ██║██║     
${MAGENTA}██████╔╝███████║██║     █████╔╝ ███████║███████║██║   ██║██║     
${MAGENTA}██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══██║██╔══██║██║   ██║██║     
${MAGENTA}██████╔╝██║  ██║╚██████╗██║  ██╗██║  ██║██║  ██║╚██████╔╝███████╗
${MAGENTA}╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
${MAGENTA}███████╗ █████╗ ███████╗██╗   ██╗
${MAGENTA}██╔════╝██╔══██╗██╔════╝╚██╗ ██╔╝
${MAGENTA}█████╗  ███████║███████╗ ╚████╔╝ 
${MAGENTA}██╔══╝  ██╔══██║╚════██║  ╚██╔╝  
${MAGENTA}███████╗██║  ██║███████║   ██║   
${MAGENTA}╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝   
${NC}"

# Check for root permission
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

SYS_PATH="/etc/sysctl.conf"
PROF_PATH="/etc/profile"

# Interactive Menu
menu() {
    clear
    echo -e "$LOGO"
    echo -e "${CYAN}Select an option:${NC}"
    echo -e "${YELLOW}1) System & Network Optimizations${NC}"
    echo -e "${YELLOW}2) Install Backhaul and Setup Tunnel${NC}"
    echo -e "${YELLOW}3) Exit${NC}"
    read -rp "Enter your choice: " choice

    case $choice in
        1)
            sysctl_optimizations
            limits_optimizations
            read -rp "Would you like to reboot now? (y/n): " REBOOT
            clear
            [[ $REBOOT =~ ^[Yy]$ ]] && reboot
            ;;
        2)
            setup_backhaul
            clear
            ;;
        3)
            clear
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            ;;
    esac
    read -rp "Press any key to return to menu..." -n1
    menu
}

# Network Optimization
sysctl_optimizations() {
    cp $SYS_PATH /etc/sysctl.conf.bak
    sed -i '/^#/d;/^$/d' "$SYS_PATH"
    cat <<EOF >> "$SYS_PATH"
fs.file-max = 67108864
net.core.default_qdisc = fq_codel
net.core.netdev_max_backlog = 32768
net.core.optmem_max = 262144
net.core.somaxconn = 65536
EOF
    sysctl -p &>/dev/null
}

# Ulimit Optimization
limits_optimizations() {
    sed -i '/ulimit/d' "$PROF_PATH"
    echo "ulimit -n 1048576" >> "$PROF_PATH"
}

# Detect Architecture
detect_arch() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        echo "amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        echo "arm64"
    else
        echo "unsupported"
    fi
}

# Backhaul Installation & Tunnel Setup
setup_backhaul() {
    ARCH=$(detect_arch)
    [[ "$ARCH" == "unsupported" ]] && { echo -e "${RED}Unsupported architecture.${NC}"; return; }

    wget -q https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_${ARCH}.tar.gz
    tar -xzf backhaul_linux_${ARCH}.tar.gz && rm backhaul_linux_${ARCH}.tar.gz LICENSE README.md

    echo -e "${CYAN}Choose setup type:${NC}"
    echo -e "${YELLOW}1) Iran Server${NC}"
    echo -e "${YELLOW}2) Kharej Client${NC}"
    read -rp "Select option [1/2]: " TYPE

    read -rp "Enter Tunnel Port: " TUNNEL_PORT
    read -rp "Enter Token: " TOKEN

    if [[ "$TYPE" == "1" ]]; then
        read -rp "Enter Port Forwarding Rules (comma-separated): " PORTS
        PORT_ARRAY=$(echo "$PORTS" | sed 's/,/","/g')
        cat > iran${TUNNEL_PORT}.toml <<EOF
[server]
bind_addr = "0.0.0.0:${TUNNEL_PORT}"
transport = "tcp"
token = "${TOKEN}"
ports = ["${PORT_ARRAY}"]
EOF
        SERVICE_NAME="backhaul-iran${TUNNEL_PORT}"
    elif [[ "$TYPE" == "2" ]]; then
        read -rp "Enter Iran Server IP: " IRAN_IP
        cat > kharej${TUNNEL_PORT}.toml <<EOF
[client]
remote_addr = "${IRAN_IP}:${TUNNEL_PORT}"
token = "${TOKEN}"
EOF
        SERVICE_NAME="backhaul-kharej${TUNNEL_PORT}"
    else
        echo -e "${RED}Invalid choice.${NC}"
        return
    fi

    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=/root/backhaul -c /root/${SERVICE_NAME#backhaul-}.toml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable --now ${SERVICE_NAME}.service &>/dev/null
}

menu
