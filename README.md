# WDA DNS 解锁工具

一个基于 dnsmasq 的 DNS 解锁脚本，用于解锁各种流媒体服务。

## 功能特点

- 🎬 支持 500+ 流媒体域名
- 🔧 配置与脚本分离，便于维护
- 🌍 支持全球主流流媒体平台
- 🤖 支持 AI 平台 (OpenAI, Claude, Gemini 等)

## 支持的服务

| 地区 | 服务 |
|------|------|
| 全球 | Netflix, Disney+, Amazon Prime Video, HBO Max, YouTube |
| 美国 | Hulu, Peacock, Paramount+, ESPN+, NFL, NBA TV |
| 英国 | BBC iPlayer, ITV Hub, Channel 4, Sky GO, BritBox |
| 日本 | Abema, TVer, U-NEXT, DMM, NicoNico, Hulu JP |
| 台湾 | KKTV, LiTV, 4GTV, 巴哈姆特动画疯, friDay影音 |
| 香港 | myTV SUPER, Viu TV, Now E, HOY TV |
| 韩国 | Wavve, Tving, Coupang Play |
| 澳洲 | Stan, 9Now, 7plus, Optus Sport |
| AI | OpenAI/ChatGPT, Claude, Gemini, Copilot |

## 文件结构

```
wda_dns/
├── unlock.sh      # 主脚本
├── domains.conf   # 域名配置文件
└── README.md      # 说明文档
```

## 使用方法

### 安装并启用 DNS 解锁

```bash
# 将 IP 替换为你的解锁服务器 IP
sudo bash unlock.sh <解锁服务器IP>
```

### 恢复原始 DNS 设置

```bash
sudo bash unlock.sh r
```

### 查看当前 DNS 状态

```bash
bash unlock.sh
```

## 自定义域名

编辑 `domains.conf` 文件即可添加或删除域名：

```bash
# 查看配置
cat domains.conf

# 添加新域名
echo "newdomain.com" >> domains.conf

# 编辑配置
vim domains.conf
```

配置文件格式：
- 每行一个域名
- 以 `#` 开头的行为注释
- 空行会被自动忽略

## 系统要求

- CentOS 7+ / Debian 9+ / Ubuntu 18.04+
- Root 权限

## 注意事项

1. 运行脚本后需要重启代理服务（如 ss/v2ray/trojan）才能生效
2. 使用 `ping netflix.com` 验证解锁是否成功
3. DNS 备份文件保存在 `/etc/resolv.conf.bak`

## License

MIT License
