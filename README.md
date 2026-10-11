# WDA DNS 分流工具

仅将列表中的域名查询转发给指定的**解锁 DNS 服务器**，其他域名走原始的非回环上游 DNS。参考 [NodeSeek 教程](https://www.nodeseek.com/post-377672-1)，使用 dnsmasq 的 `server=/domain/DNS`，不再用 `address=` 将所有域名强制映射到同一 IP。

## 使用

要求 Linux、systemd、root、util-linux（flock），支持 Debian/Ubuntu 和 yum/dnf 系统。先下载本修复版本的所有文件，再运行：

```bash
sudo bash wda_dns.sh 22.22.22.22
# 指定其他本地域名文件
sudo bash wda_dns.sh 22.22.22.22 ./domains.conf
sudo bash wda_dns.sh s
sudo bash wda_dns.sh r
bash wda_dns.sh h
```

IP 需替换为你实际获授权使用的解锁 DNS 地址，而不是普通流媒体落地 IP。本地同目录存在 `domains.conf` 时优先使用；否则从脚本中的 `DOMAINS_URL` 下载。一键运行时会从 GitHub 下载域名列表：

```bash
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/wda_dns.sh) 22.22.22.22'
```

更新域名时下载新的列表并重新运行安装命令。

## 修复行为

- `server=/域名/解锁DNS` 保留 DNS 查询语义；普通 DNS 上游来自首次安装备份，去除回环地址，不开启 `all-servers`。
- 使用独立的 `wda-dns.service` 和 `/etc/wda-dns.conf`，只绑定 `127.0.0.1:53`。端口冲突会启动失败并回滚，不自动停止其他 DNS 服务。
- 下载检查 HTTP 错误、超时；域名小写化、去重、校验格式。空列表和 HTML 错误页直接拒绝。
- 首次备份保存在 `/var/lib/wda-dns`，重复安装不覆盖；保存 resolv.conf 对象及内容，恢复时保留原符号链接。
- 配置语法检查、服务启动、分流域名和普通域名 A 查询通过后才切换系统 DNS。安装失败恢复前一次配置与服务状态。
- 不使用 `chattr +i` 锁定系统 DNS；对于旧版锁定文件，迁移时解除锁定，失败则重新锁定。
- 旧版存在 `/etc/dnsmasq.d/wda_dns.conf` 时使用 `/etc/resolv.dnsmasq.conf` 备份升级，移除旧规则并停止旧 dnsmasq。恢复时会重新启动原先运行的 dnsmasq，但不恢复旧解锁规则。其他原有配置不会删除。
- 无有效备份时恢复命令报错，不擅自写入公共 DNS。

## 验证与边界

```bash
systemctl status wda-dns
journalctl -u wda-dns -n 50
# 指定本地服务，确认查询能正常完成
dig @127.0.0.1 netflix.com
dig @127.0.0.1 example.com
# 确认系统默认查询走本地服务
dig netflix.com
```

解析结果不需要等于解锁 DNS 的 IP。DNS 成功只证明解析可用，不能证明流媒体账户、地区和实际播放已经解锁。代理应用若自带 DNS 或 DoH，需要配置其使用本机解析；重启代理不能保证覆盖其自带 DNS。

NetworkManager、systemd-resolved、DHCP 或云初始化可能重新管理 `/etc/resolv.conf`。此版本切换时保存并替换原链接，不修改这些管理器的持久配置；重启后需再次检查。原 DNS 如果全为回环地址会拒绝安装，需要先提供真实上游。`resolv.conf` 是容器挂载点时可能无法替换，安装会报错并尝试回滚。

安装依赖可能更改系统软件包，这些包不会在回滚或恢复时卸载。升级旧版时，如果旧备份本身已经被重复执行破坏为 `127.0.0.1`，脚本会拒绝继续，不会猜测原始 DNS。

## 回归测试

```bash
bash -n wda_dns.sh
python3 -m unittest discover -s tests -v
```

测试使用临时文件及模拟服务命令，不修改系统 DNS。覆盖规则生成、非法输入、仓库域名校验、重复安装、链接恢复、查询失败回滚和错误列表拒绝。还需在目标 Linux 服务器验证真实 systemd/dnsmasq 行为与播放效果。

## 截图服务的域名补充

补充了 Apple TV、Meta AI、JetBrains AI、JAVBus 的入口和已确认接口，以及 YouTube、Steam、Google Play、OpenAI 的部分遗漏域名，共新增 25 条，当前 595 个唯一域名。`google.com` 已覆盖的子域名不重复添加。JAV 按截图的 JAVBus 图标处理。

参考来源：[Apple TV 规则](https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/AppleTV/AppleTV.list)、[YouTube 规则](https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.list)、[Steam 规则](https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Steam/Steam.list)、[Meta 官方入口](https://ai.meta.com/meta-ai/)、[JetBrains AI 接口文档](https://www.jetbrains.com/help/datalore/configure-ai-assistance.html)、[Google 网络要求](https://support.google.com/work/android/answer/10513641?hl=en)、[OpenAI 网络建议](https://help.openai.com/en/articles/9247338-network-recommendations-for-chatgpt-errors-on-web-and-apps)。网络允许清单和社区分流规则作为候选来源，不能证明所有条目都是解锁必需域名，也不能保证播放、免广告或登录成功。
