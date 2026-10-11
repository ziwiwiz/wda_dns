#!/usr/bin/env bash
# Domain-specific DNS forwarding. Requires Linux, systemd and root for mutations.
set -Eeuo pipefail
DOMAINS_URL=https://raw.githubusercontent.com/ziwiwiz/wda_dns/main/domains.conf
STATE=/var/lib/wda-dns
CONFIG=/etc/wda-dns.conf
UNIT=/etc/systemd/system/wda-dns.service
RESOLV=/etc/resolv.conf
LEGACY=/etc/dnsmasq.d/wda_dns.conf
LEGACY_BACKUP=/etc/resolv.dnsmasq.conf
SERVICE=wda-dns.service
TMP=
TRANSACTION=0
fail() { printf '错误: %s\n' "$*" >&2; return 1; }
valid_ip() {
    local ip=$1 part
    [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local -a parts
    IFS=. read -r -a parts <<< "$ip"
    for part in "${parts[@]}"; do
        [[ ${#part} -le 3 ]] && ((10#$part <= 255)) || return 1
    done
    [[ $ip != 0.* && $ip != 127.* && $ip != 255.255.255.255 ]]
}
normalize_domains() {
    LC_ALL=C awk '
    { sub(/#.*/, ""); gsub(/\r/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); if ($0 == "") next
      d=tolower($0); n=split(d,a,"."); good=(n>=2 && length(d)<=253)
      for(i=1;i<=n;i++) if(length(a[i])>63 || a[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) good=0
      if(!good) { print "非法域名，第 " NR " 行: " $0 > "/dev/stderr"; bad=1 }
      else if(!seen[d]++) print d
    } END { if(bad) exit 1 }' "$1"
}
generate_config() {
    local ip=$1 domains=$2 upstream=$3
    printf '%s\n' 'domain-needed' 'bogus-priv' 'listen-address=127.0.0.1' 'bind-interfaces' 'no-resolv' 'cache-size=2048'
    while read -r ns; do printf 'server=%s\n' "$ns"; done < "$upstream"
    while read -r domain; do printf 'server=/%s/%s\n' "$domain" "$ip"; done < "$domains"
}
extract_upstream() {
    awk '$1=="nameserver" && $2 !~ /^127\./ && $2!="::1" && !seen[$2]++ {print $2}' "$1"
}
require_root() {
    [[ $EUID == 0 ]] || fail '请使用 sudo 运行安装或恢复。'
    [[ $(uname -s) == Linux ]] || fail '仅支持 Linux。'
    command -v systemctl >/dev/null || fail '需要 systemd。'
    command -v flock >/dev/null || fail '需要 util-linux 的 flock。'
    exec 9>/run/wda-dns.lock
    flock -n 9 || fail '另一个实例正在运行。'
}
# Preserve both the resolver object (possibly a symlink) and its current contents.
snapshot() {
    local dir=$1 path=$2 name=$3
    if [[ -e $path || -L $path ]]; then cp -a -- "$path" "$dir/$name"; fi
}
restore_object() {
    local dir=$1 path=$2 name=$3
    rm -f -- "$path"
    if [[ -e $dir/$name || -L $dir/$name ]]; then cp -a -- "$dir/$name" "$path"; fi
}
rollback() {
    printf '安装失败，正在回滚配置与 DNS。\n' >&2
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    restore_object "$TMP" "$RESOLV" resolver
    restore_object "$TMP" "$CONFIG" config
    restore_object "$TMP" "$UNIT" unit
    restore_object "$TMP" "$LEGACY" legacy
    systemctl daemon-reload || true
    if [[ -f $TMP/was-enabled ]]; then systemctl enable "$SERVICE" >/dev/null 2>&1 || true
    else systemctl disable "$SERVICE" >/dev/null 2>&1 || true; fi
    if [[ -f $TMP/was-active ]]; then systemctl restart "$SERVICE" || true; fi
    if [[ -f $TMP/legacy-active ]]; then systemctl start dnsmasq || true; fi
    if [[ -f $TMP/new-state ]]; then rm -rf -- "$STATE"; fi
    if [[ -f $TMP/immutable ]]; then chattr +i "$RESOLV" || true; fi
}
cleanup() {
    local rc=$?
    trap - EXIT
    if ((TRANSACTION)); then rollback; fi
    if [[ -n $TMP ]]; then rm -rf -- "$TMP"; fi
    exit "$rc"
}
install_deps() {
    if command -v dnsmasq >/dev/null && command -v curl >/dev/null && command -v dig >/dev/null; then return; fi
    # Debian's base package does not start the distribution dnsmasq service.
    if command -v apt-get >/dev/null; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq-base curl dnsutils
    elif command -v dnf >/dev/null; then dnf install -y dnsmasq curl bind-utils
    elif command -v yum >/dev/null; then yum install -y dnsmasq curl bind-utils
    else fail '支持 Debian/Ubuntu 和使用 yum/dnf 的系统。'; fi
}
probe() {
    local domain=$1 response
    if ! response=$(dig @127.0.0.1 "$domain" A +time=5 +tries=2 +noall +comments +answer 2>&1); then
        printf 'DNS 检测失败 (%s):\n%s\n' "$domain" "$response" >&2
        return 1
    fi
    # NOERROR with no A records is a valid NODATA response, not a resolver failure.
    if [[ $response == *'status: NOERROR,'* ]]; then
        printf 'DNS 响应正常: %s（不代表流媒体已解锁）\n' "$domain"
        return 0
    fi
    printf 'DNS 检测返回异常状态 (%s):\n%s\n' "$domain" "$response" >&2
    return 1
}
probe_unlock() {
    local domains=$1 domain
    # Try independent services where present; custom lists fall back to their first entries.
    for domain in netflix.com disneyplus.com; do
        if grep -Fxq "$domain" "$domains" && probe "$domain"; then return 0; fi
    done
    while IFS= read -r domain; do
        if probe "$domain"; then return 0; fi
    done < <(head -n 3 "$domains")
    return 1
}
unlock() {
    local ip=$1 file=${2:-} source
    if [[ -z $file && -f ${BASH_SOURCE[0]%/*}/domains.conf ]]; then file=${BASH_SOURCE[0]%/*}/domains.conf; fi
    valid_ip "$ip" || fail '需要有效的非回环 IPv4 解锁 DNS 地址。'
    require_root
    TMP=$(mktemp -d)
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    install_deps
    if [[ -n $file ]]; then cp -- "$file" "$TMP/raw"
    else curl --fail --show-error --silent --location --connect-timeout 10 --max-time 60 --retry 2 "$DOMAINS_URL" -o "$TMP/raw"; fi
    normalize_domains "$TMP/raw" > "$TMP/domains"
    [[ -s $TMP/domains ]] || fail '域名列表为空。'
    snapshot "$TMP" "$RESOLV" resolver
    snapshot "$TMP" "$CONFIG" config
    snapshot "$TMP" "$UNIT" unit
    snapshot "$TMP" "$LEGACY" legacy
    systemctl is-active --quiet "$SERVICE" && touch "$TMP/was-active"
    systemctl is-enabled --quiet "$SERVICE" && touch "$TMP/was-enabled"
    if [[ -f $LEGACY ]] && systemctl is-active --quiet dnsmasq; then touch "$TMP/legacy-active"; fi
    if [[ -d $STATE ]]; then
        [[ -f $STATE/ready ]] || fail '备份状态不完整，请检查 /var/lib/wda-dns。'
        source=$STATE/original-content
    elif [[ -f $LEGACY ]]; then
        [[ -s $LEGACY_BACKUP ]] || fail '旧版本备份缺失，不能安全升级。'
        source=$LEGACY_BACKUP
    else source=$RESOLV; fi
    extract_upstream "$source" > "$TMP/upstream"
    [[ -s $TMP/upstream ]] || fail '原始 DNS 只有回环地址；请先配置可用的非回环上游 DNS。'
    generate_config "$ip" "$TMP/domains" "$TMP/upstream" > "$TMP/config-new"
    dnsmasq --test --conf-file="$TMP/config-new"
    # Do not silently remove an administrator's immutable flag.
    TRANSACTION=1
    if command -v lsattr >/dev/null && [[ $(lsattr -d "$RESOLV" 2>/dev/null || true) == *i*' '* ]]; then
        if [[ -f $LEGACY ]]; then touch "$TMP/immutable"; chattr -i "$RESOLV"
        else fail 'resolv.conf 已锁定，请先由管理员解除不可变属性。'; fi
    fi
    TRANSACTION=1
    if [[ ! -d $STATE ]]; then
        touch "$TMP/new-state"
        install -d -m 700 "$STATE"
        if [[ -f $LEGACY ]]; then
            cp -a "$LEGACY_BACKUP" "$STATE/original-resolver"
            [[ ! -f $TMP/legacy-active ]] || touch "$STATE/legacy-active"
        else cp -a "$RESOLV" "$STATE/original-resolver"; fi
        cat "$source" > "$STATE/original-content"
        touch "$STATE/ready"
    fi
    if [[ -f $LEGACY ]]; then
        systemctl stop dnsmasq
        rm -f "$LEGACY"
    fi
    install -m 644 "$TMP/config-new" "$CONFIG"
    local binary
    binary=$(command -v dnsmasq)
    cat > "$UNIT" <<UNITEOF
[Unit]
Description=WDA domain-specific DNS forwarding
After=network.target
[Service]
ExecStart=$binary --keep-in-foreground --conf-file=$CONFIG
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNITEOF
    systemctl daemon-reload
    systemctl restart "$SERVICE"
    systemctl is-active --quiet "$SERVICE"
    probe_unlock "$TMP/domains" || fail '多个分流域名均未获得正常 DNS 响应，详见上方查询结果。'
    probe example.com || fail '普通域名 DNS 查询失败。'
    # Replace the link itself; its target is untouched and saved for restoration.
    { printf 'nameserver 127.0.0.1\n'; awk '$1=="search" || $1=="domain" || $1=="options"' "$STATE/original-content"; } > "$TMP/resolver-new"
    install -m 644 "$TMP/resolver-new" "${RESOLV}.wda-new"
    mv -f "${RESOLV}.wda-new" "$RESOLV"
    systemctl enable "$SERVICE"
    local count
    count=$(wc -l < "$TMP/domains" | tr -d ' ')
    TRANSACTION=0
    rm -rf -- "$TMP"
    TMP=
    printf '已配置 %s 个域名，解锁 DNS: %s。请另行验证实际流媒体播放。\n' "$count" "$ip"
}
restore_dns() {
    require_root
    [[ -f $STATE/ready ]] || fail '没有本工具的恢复备份；不会替换成公共 DNS。'
    # Restore DNS first, before stopping the local resolver.
    restore_object "$STATE" "$RESOLV" original-resolver
    systemctl disable --now "$SERVICE"
    rm -f "$CONFIG" "$UNIT"
    systemctl daemon-reload
    if [[ -f $STATE/legacy-active ]]; then systemctl start dnsmasq; fi
    rm -rf -- "$STATE"
    printf '已恢复原始 DNS（包括原有符号链接），移除 WDA 服务。\n'
}
show_status() {
    cat "$RESOLV"
    systemctl is-active "$SERVICE" || true
    if [[ -f $CONFIG ]]; then awk '/^server=\//{n++} END{print "分流规则: " n+0}' "$CONFIG"; fi
}
main() {
    case ${1:-s} in
        h|help|-h|--help) printf '用法: %s <IPv4解锁DNS> [本地域名文件] | r | s | h\n' "$0" ;;
        r|restore) [[ $# == 1 ]] || fail '恢复命令不接受额外参数。'; restore_dns ;;
        s|status) show_status ;;
        *) [[ $# -le 2 ]] || fail '参数过多。'; unlock "$@" ;;
    esac
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
