#!/bin/bash
# WDA DNS 解锁工具
# GitHub: https://github.com/ziwiwiz/wda_dns

green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
red='\033[0;31m'
green_prefix="[${green}OK${plain}]"
yellow_prefix="[${yellow}Info${plain}]"
red_prefix="[${red}Error${plain}]"

# GitHub Raw URL
DOMAINS_URL="https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/domains.conf"

# 检测系统类型
detect_os() {
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        OS="centos"
    elif grep -Eqi "Red Hat" /etc/issue || grep -Eq "Red Hat" /etc/*-release; then
        OS="centos"
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        OS="debian"
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        OS="ubuntu"
    else
        echo -e "${red_prefix} 此脚本仅支持 CentOS、Ubuntu 和 Debian 系统"
        exit 1
    fi
}

# 安装依赖
install_deps() {
    echo -e "${yellow_prefix} 检测到系统: ${OS}"
    echo -e "${yellow_prefix} 正在安装依赖..."
    
    case $OS in
        centos)
            yum install -y epel-release >/dev/null 2>&1
            yum install -y bind-utils dnsmasq curl >/dev/null 2>&1
            ;;
        debian|ubuntu)
            apt-get update >/dev/null 2>&1
            apt-get install -y dnsutils dnsmasq curl >/dev/null 2>&1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${green_prefix} 依赖安装完成"
    else
        echo -e "${red_prefix} 依赖安装失败，请检查网络连接"
        exit 1
    fi
}

# 生成 dnsmasq 配置（直接从 GitHub 读取域名）
generate_dnsmasq_config() {
    local UNLOCK_IP=$1
    
    echo -e "${yellow_prefix} 正在从 GitHub 读取域名配置..."
    
    # 获取域名列表
    if command -v curl &> /dev/null; then
        DOMAINS_CONTENT=$(curl -sL "$DOMAINS_URL")
    elif command -v wget &> /dev/null; then
        DOMAINS_CONTENT=$(wget -qO- "$DOMAINS_URL")
    else
        echo -e "${red_prefix} 未找到 curl 或 wget"
        exit 1
    fi
    
    if [ -z "$DOMAINS_CONTENT" ]; then
        echo -e "${red_prefix} 无法获取域名配置，请检查网络连接"
        exit 1
    fi
    
    # 生成基础配置
    cat > /etc/dnsmasq.d/wda_dns.conf <<EOF
domain-needed
bogus-priv
no-resolv
no-poll
all-servers
server=8.8.8.8
server=1.1.1.1
cache-size=2048
local-ttl=60
interface=*
EOF

    # 解析域名并追加到配置
    local count=0
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释行
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        if [ -n "$line" ]; then
            echo "address=/${line}/${UNLOCK_IP}" >> /etc/dnsmasq.d/wda_dns.conf
            ((count++))
        fi
    done <<< "$DOMAINS_CONTENT"
    
    echo -e "${green_prefix} 已加载 ${count} 个域名"
}

# 主解锁函数
unlock() {
    local UNLOCK_IP=$1
    
    detect_os
    install_deps
    
    systemctl enable dnsmasq >/dev/null 2>&1
    chattr -i /etc/resolv.conf 2>/dev/null
    
    # 备份 DNS 配置
    if [ ! -f '/etc/resolv.conf.bak' ]; then
        cp -f /etc/resolv.conf /etc/resolv.conf.bak
    fi
    
    rm -f /etc/resolv.conf
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    chattr +i /etc/resolv.conf
    
    # 生成 dnsmasq 配置
    generate_dnsmasq_config "$UNLOCK_IP"
    
    systemctl restart dnsmasq
    
    if systemctl is-active --quiet dnsmasq; then
        echo -e "${green_prefix} dnsmasq 启动成功"
    else
        echo -e "${red_prefix} dnsmasq 启动失败"
        exit 1
    fi
    
    echo ""
    echo -e "${yellow_prefix} 系统当前 DNS（显示为 127.0.0.1 是正常的）"
    echo "---------------------"
    cat /etc/resolv.conf
    echo ""
    echo -e "${yellow_prefix} DNS 备份文件: /etc/resolv.conf.bak"
    echo "---------------------"
    cat /etc/resolv.conf.bak
    echo ""
    echo -e "${green_prefix} 解锁配置完成！"
    echo -e "${yellow_prefix} 验证方法: ping netflix.com（应返回 ${UNLOCK_IP}）"
    echo -e "${yellow_prefix} 需要重启代理服务（ss/v2ray/trojan 等）后解锁才会生效"
}

# 恢复 DNS
restore_dns() {
    if [ -f '/etc/resolv.conf.bak' ]; then
        echo -e "${yellow_prefix} 检测到 DNS 备份文件，正在恢复..."
        chattr -i /etc/resolv.conf 2>/dev/null
        rm -f /etc/resolv.conf
        cp -f /etc/resolv.conf.bak /etc/resolv.conf
    else
        echo -e "${yellow_prefix} 没有备份 DNS 文件，使用通用 DNS"
        chattr -i /etc/resolv.conf 2>/dev/null
        cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    fi
    
    echo -e "${yellow_prefix} 正在禁用 dnsmasq 服务..."
    systemctl stop dnsmasq 2>/dev/null
    systemctl disable dnsmasq 2>/dev/null
    
    # 清理配置文件
    rm -f /etc/dnsmasq.d/wda_dns.conf
    
    echo -e "${green_prefix} 完成! 当前系统 DNS:"
    echo "---------------------"
    cat /etc/resolv.conf
}

# 显示状态
show_status() {
    echo -e "${yellow_prefix} 当前系统 DNS"
    echo "---------------------"
    cat /etc/resolv.conf
    echo ""
    
    if systemctl is-active --quiet dnsmasq; then
        echo -e "${green_prefix} dnsmasq 服务状态: 运行中"
        
        if [ -f /etc/dnsmasq.d/wda_dns.conf ]; then
            DOMAIN_COUNT=$(grep -c '^address=' /etc/dnsmasq.d/wda_dns.conf 2>/dev/null || echo 0)
            UNLOCK_IP=$(grep -m1 '^address=' /etc/dnsmasq.d/wda_dns.conf 2>/dev/null | sed 's/.*\///' | head -1)
            echo -e "${yellow_prefix} 解锁域名数量: ${DOMAIN_COUNT}"
            echo -e "${yellow_prefix} 解锁服务器 IP: ${UNLOCK_IP}"
        fi
    else
        echo -e "${yellow_prefix} dnsmasq 服务状态: 未运行"
    fi
}

# 显示帮助
show_help() {
    echo "WDA DNS 解锁工具"
    echo ""
    echo "用法:"
    echo "  $0 <解锁服务器IP>  - 安装并启用 DNS 解锁"
    echo "  $0 r              - 恢复原始 DNS 设置"
    echo "  $0 s              - 显示当前状态"
    echo "  $0 h              - 显示帮助信息"
    echo ""
    echo "示例:"
    echo "  sudo $0 1.2.3.4   - 使用 1.2.3.4 作为解锁服务器"
    echo "  sudo $0 r         - 恢复原始 DNS"
}

# 主入口
case "$1" in
    "")
        show_status
        ;;
    "r"|"restore")
        restore_dns
        ;;
    "s"|"status")
        show_status
        ;;
    "h"|"help"|"-h"|"--help")
        show_help
        ;;
    *)
        # 验证 IP 格式
        if [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            unlock "$1"
        else
            echo -e "${red_prefix} 无效的 IP 地址: $1"
            echo "使用 '$0 h' 查看帮助"
            exit 1
        fi
        ;;
esac