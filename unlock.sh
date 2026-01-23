#!/bin/bash
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
red='\033[0;31m'
green=[${green}OK${plain}] 
yellow=[${yellow}Info${plain}] 
red=[${red}Error${plain}] 

unlock(){
if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    yum install bind-utils
    echo y | yum install -y dnsmasq
elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
    apt-get update
    apt-get install dnsutils
    apt install -y dnsmasq
elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
    apt-get update
    apt-get install dnsutils
    apt install -y dnsmasq
else
    echo "This script only supports CentOS, Ubuntu and Debian."
    exit 1
fi

if [ $? -eq 0 ]; then
	systemctl enable dnsmasq
	chattr -i /etc/resolv.conf
	
	if [ ! -f '/etc/resolv.conf.bak' ];then
		cp -f /etc/resolv.conf /etc/resolv.conf.bak
	fi
	rm -f /etc/resolv.conf
	echo "nameserver 127.0.0.1" > /etc/resolv.conf
	chattr +i /etc/resolv.conf
	# 配置文件路径（与脚本同目录）
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	DOMAINS_FILE="${SCRIPT_DIR}/domains.conf"
	
	# 检查配置文件是否存在
	if [ ! -f "$DOMAINS_FILE" ]; then
		echo -e "${red} 域名配置文件不存在: $DOMAINS_FILE"
		exit 1
	fi
	
	# 生成基础配置
	cat > /etc/dnsmasq.d/unlock.conf <<EOF
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
	
	# 从配置文件读取域名并追加到配置
	while IFS= read -r line || [ -n "$line" ]; do
		# 跳过空行和注释行
		line=$(echo "$line" | sed 's/#.*//' | xargs)
		if [ -n "$line" ]; then
			echo "address=/${line}/$1" >> /etc/dnsmasq.d/unlock.conf
		fi
	done < "$DOMAINS_FILE"
	
	echo -e "${yellow} 已从配置文件加载 $(grep -c '^address=' /etc/dnsmasq.d/unlock.conf) 个域名"

fi

    systemctl restart dnsmasq
    echo -e "${green} dnsmasq启动成功"
    echo ""
    echo -e "${yellow} 系统当前DNS（显示为127.0.0.1是正常）"
    echo "---------------------"
    cat /etc/resolv.conf
    echo ""
    echo -e "${yellow} DNS备份文件 /etc/resolv.conf.bak"
    echo "---------------------"
    cat /etc/resolv.conf.bak
    echo ""
    echo -e "${yellow} ping netflix.com为你落地机的ip说明解锁成功"
    echo -e "${yellow} 需要重启你的ss/v2/trojan等代理服务解锁才会生效"
else
    echo -e "${red} dnsmasq安装失败, 请检查仓库状况"
fi
}

re_dns(){
if [ -f '/etc/resolv.conf.bak' ];then
	echo -e "${yellow} 检测到DNS备份文件，从备份文件恢复系统DNS设置..."
	chattr -i /etc/resolv.conf
	rm -f /etc/resolv.conf
	cp -f /etc/resolv.conf.bak /etc/resolv.conf
else
	echo -e "${yellow} 没有备份DNS文件，使用通用DNS"
	chattr -i /etc/resolv.conf
	cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
fi
	echo -e "${yellow} 禁用dnsmasq服务..."
	systemctl stop dnsmasq
	systemctl disable dnsmasq
	echo -e "${green} 完成，查看当前系统DNS（不是127.0.0.1说明成功）"
	echo "---------------------"
	cat /etc/resolv.conf
}

case "$1" in
"")
echo -e "${yellow} 当前系统DNS"
echo "---------------------"
cat /etc/resolv.conf
;;

"r")
re_dns
;;

#else
*)
unlock $1
;;
esac