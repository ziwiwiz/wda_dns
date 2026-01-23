# WDA DNS 解锁工具

一个基于 dnsmasq 的 DNS 解锁脚本，用于解锁各种流媒体服务。

## ✨ 功能特点

- 🚀 **一键安装** - 无需下载，直接在服务器上运行
- 🎬 **500+ 域名** - 支持全球主流流媒体平台
- 🔄 **实时读取** - 每次运行自动获取最新域名配置
- 🤖 **AI 平台支持** - OpenAI、Claude、Gemini 等

## 🎯 支持的服务

| 地区 | 服务 |
|------|------|
| 🌍 全球 | Netflix, Disney+, Amazon Prime Video, HBO Max, YouTube |
| 🇺🇸 美国 | Hulu, Peacock, Paramount+, ESPN+, NFL, NBA TV |
| 🇬🇧 英国 | BBC iPlayer, ITV Hub, Channel 4, Sky GO, BritBox |
| 🇯🇵 日本 | Abema, TVer, U-NEXT, DMM, NicoNico, Hulu JP |
| 🇹🇼 台湾 | KKTV, LiTV, 4GTV, 巴哈姆特动画疯, friDay影音 |
| 🇭🇰 香港 | myTV SUPER, Viu TV, Now E, HOY TV |
| 🇰🇷 韩国 | Wavve, Tving, Coupang Play |
| 🇦🇺 澳洲 | Stan, 9Now, 7plus, Optus Sport |
| 🤖 AI | OpenAI/ChatGPT, Claude, Gemini, Copilot |

## 🚀 快速开始

### 一键安装（推荐）

在你的**落地机/代理服务器**上执行以下命令：

```bash
# 使用 curl（将 YOUR_IP 替换为你的解锁服务器 IP）
bash <(curl -sL https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) YOUR_IP

# 或使用 wget
bash <(wget -qO- https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) YOUR_IP
```

### 示例

```bash
# 假设解锁服务器 IP 为 1.2.3.4
bash <(curl -sL https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) 1.2.3.4
```

### 恢复原始设置

```bash
bash <(curl -sL https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) r
```

### 查看状态

```bash
bash <(curl -sL https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) s
```

## ⚙️ 命令参考

| 命令 | 说明 |
|------|------|
| `wda_dns.sh <IP>` | 使用指定 IP 启用 DNS 解锁 |
| `wda_dns.sh r` | 恢复原始 DNS 设置 |
| `wda_dns.sh s` | 查看当前状态 |
| `wda_dns.sh h` | 显示帮助信息 |

## 🔍 验证解锁

### 流媒体解锁检测

使用第三方脚本检测解锁状态：

```bash
bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)
```

### 手动验证

```bash
# 检查 Netflix 解析（应返回解锁服务器 IP）
ping netflix.com

# 检查 Disney+ 解析
ping disneyplus.com
```

## 🛠️ 常用命令

### dnsmasq 服务管理

```bash
# 启动并设置开机自启
systemctl enable dnsmasq && systemctl start dnsmasq

# 停止并禁用开机自启
systemctl stop dnsmasq && systemctl disable dnsmasq

# 重启并查看状态
systemctl restart dnsmasq && systemctl status dnsmasq
```

### 系统 DNS 管理

```bash
# 查看本机 DNS
cat /etc/resolv.conf

# 锁定 DNS 文件（防止被修改）
chattr +i /etc/resolv.conf

# 解锁 DNS 文件（允许修改）
chattr -i /etc/resolv.conf
```

## 🔧 自定义域名

如需添加自定义域名，可以 Fork 本仓库后修改 `domains.conf` 文件。

配置文件格式：
- 每行一个域名
- 以 `#` 开头的行为注释
- 空行会被自动忽略

## 💻 系统要求

- **系统**: CentOS 7+ / Debian 9+ / Ubuntu 18.04+
- **权限**: Root 权限
- **网络**: 能访问 GitHub

## ⚠️ 注意事项

1. 运行脚本后需要**重启代理服务**（如 ss/v2ray/trojan）才能生效
2. 使用 `ping netflix.com` 验证解锁是否成功（应返回解锁服务器 IP）
3. DNS 备份文件保存在 `/etc/resolv.conf.bak`
4. 每次执行都会从 GitHub 获取最新域名配置

## 📝 常见问题

### Q: 如何确认解锁成功？
A: 运行 `ping netflix.com`，如果返回的 IP 是你设置的解锁服务器 IP，说明解锁配置成功。

### Q: 解锁后流媒体还是无法访问？
A: 请确保：
1. 重启了代理服务
2. 解锁服务器本身可以访问对应流媒体

### Q: 如何更新域名列表？
A: 重新运行安装命令即可，脚本会自动获取最新配置。

### Q: 如何完全卸载？
A: 运行恢复命令 `bash <(curl -sL ...) r` 即可恢复原始设置。

## 📜 License

MIT License
