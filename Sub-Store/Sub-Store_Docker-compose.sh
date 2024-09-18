#!/bin/bash

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "运行脚本需要 root 权限" >&2
        exit 1
    fi
}

install_basic_tools() {
    apt-get update -y
    apt-get install -y curl gnupg lsb-release iptables net-tools netfilter-persistent software-properties-common
    echo "基础工具已安装。"
}

clean_system() {
    for proc in dpkg apt apt-get; do
        pids=$(ps -ef | grep $proc | grep -v grep | awk '{print $2}')
        [ -n "$pids" ] && sudo kill -9 $pids 2>/dev/null || true
    done

    sudo dpkg --configure -a
    sudo apt-get clean -y
    sudo apt-get autoclean -y
    sudo apt-get autoremove -y
}

install_packages() {
    apt-get update -y
    apt-get install -y curl gnupg lsb-release

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io

    if ! command -v docker-compose &> /dev/null; then
        LATEST_COMPOSE_VERSION=$(curl -sS https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
        curl -fsSL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    systemctl enable docker
    systemctl start docker

    docker --version
    docker-compose --version
}

get_public_ip() {
    local ip_services=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ipecho.net/plain" "ident.me")
    for service in "${ip_services[@]}"; do
        public_ip=$(curl -sS "$service")
        if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$public_ip"
            return
        fi
        sleep 1
    done
    echo "无法获取公共 IP 地址。" >&2
    exit 1
}

setup_environment() {
    sudo locale-gen en_US.UTF-8 && sudo update-locale LANG=en_US.UTF-8 && sudo timedatectl set-timezone Asia/Shanghai
    echo -e 'nameserver 8.8.4.4\nnameserver 8.8.8.8' > /etc/resolv.conf
    
    iptables -A INPUT -p udp --dport 60000:61000 -j ACCEPT
    iptables -A INPUT -p tcp --tcp-flags SYN SYN -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    netfilter-persistent reload
    
    echo 0 > /proc/sys/net/ipv4/tcp_fastopen
    docker system prune -af --volumes
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf && sysctl -p > /dev/null
}

setup_docker() {
    local secret_key=$(openssl rand -hex 16)
    cat <<EOF > docker-compose.yml
services:
  sub-store:
    image: xream/sub-store
    container_name: sub-store
    restart: always
    environment:
      - SUB_STORE_BACKEND_UPLOAD_CRON=55 23 * * *
      - SUB_STORE_FRONTEND_BACKEND_PATH=/$secret_key
    ports:
      - "3001:3001"
    volumes:
      - /root/sub-store-data:/opt/app/data

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc/localtime:/etc/localtime:ro
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=3600
      - WATCHTOWER_NOTIFICATION_URL=telegram://7263415842:AAG39tVwzxyiarORYfYvD0lIMYK6ePs7lac@telegram?chats=-7263415842
      - WATCHTOWER_NOTIFICATION_TITLE_TAG=Sub-Store Update
EOF

    # 启动 Docker 容器并检查是否成功
    docker-compose up -d || { echo "Error: Unable to start Docker containers" >&2; exit 1; }

    echo "您的 Sub-Store 信息如下"
    echo -e "\nSub-Store面板：http://$public_ip:3001\n"
    echo -e "\n后端地址：http://$public_ip:3001/$secret_key\n"
}

main() {
    check_root
    install_basic_tools
    clean_system
    public_ip=$(get_public_ip)
    install_packages
    setup_environment
    setup_docker
}

main