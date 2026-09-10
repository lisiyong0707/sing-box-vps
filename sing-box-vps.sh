#!/usr/bin/env bash
# sing-box VPS deployer. Configuration fields and package repository follow
# https://sing-box.sagernet.org/installation/package-manager/
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/sing-box"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly STATE_DIR="/var/lib/sing-box-vps"
readonly STATE_FILE="${STATE_DIR}/connections.json"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly CERT_HOOK="/etc/letsencrypt/renewal-hooks/deploy/restart-sing-box"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { printf "${BLUE}[i]${NC} %s\n" "$*"; }
ok() { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
die() { printf "${RED}[x]${NC} %s\n" "$*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  printf "${RED}[x]${NC} 失败：第 %s 行退出（状态 %s）。\n" "$1" "$exit_code" >&2
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

require_root() {
  [[ ${EUID} -eq 0 ]] || die "请使用 sudo bash $0 运行。"
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "此脚本需要 systemd。"
}

require_apt() {
  command -v apt-get >/dev/null 2>&1 || die "当前版本支持 Debian/Ubuntu（APT）系统。"
}

ensure_dirs() {
  install -d -m 700 "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_DIR"
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '{"connections":[]}\n' > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
  fi
}

confirm() {
  local prompt=$1 default=${2:-N} answer
  read -r -p "$prompt [$([[ $default == Y ]] && printf 'Y/n' || printf 'y/N')]: " answer
  answer=${answer:-$default}
  [[ $answer =~ ^[Yy]$ ]]
}

ask_required() {
  local prompt=$1 value
  while true; do
    read -r -p "$prompt: " value
    [[ -n $value ]] && { printf '%s' "$value"; return; }
    warn "此项不能为空。"
  done
}

valid_port() {
  [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

ask_port() {
  local prompt=$1 default=$2 value
  while true; do
    read -r -p "$prompt [$default]: " value
    value=${value:-$default}
    valid_port "$value" && { printf '%s' "$value"; return; }
    warn "端口必须是 1 到 65535 的整数。"
  done
}

valid_hostname() {
  [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

detect_public_ip() {
  local ip
  for endpoint in https://api.ipify.org https://ifconfig.me/ip; do
    ip=$(curl -4fsS --connect-timeout 3 --max-time 6 "$endpoint" 2>/dev/null || true)
    [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { printf '%s' "$ip"; return; }
  done
  hostname -I 2>/dev/null | awk '{print $1}'
}

ask_server_address() {
  local default value
  default=$(detect_public_ip)
  read -r -p "客户端连接地址（公网 IP 或域名） [${default:-请填写}]: " value
  value=${value:-$default}
  [[ -n $value ]] || die "需要一个客户端可访问的地址。"
  printf '%s' "$value"
}

install_prerequisites() {
  require_apt
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl jq openssl iproute2
}

install_sing_box() {
  require_root
  require_systemd
  install_prerequisites
  info "配置 sing-box 官方 APT 软件源"
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc
  tee /etc/apt/sources.list.d/sagernet.sources >/dev/null <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
  apt-get update
  apt-get install -y sing-box
  ensure_dirs
  systemctl enable sing-box
  ok "已安装 $(sing-box version | head -n 1)"
}

ensure_installed() {
  command -v sing-box >/dev/null 2>&1 || install_sing_box
  command -v jq >/dev/null 2>&1 || install_prerequisites
  ensure_dirs
}

create_base_config() {
  [[ -f $CONFIG_FILE ]] && return
  info "创建基础配置"
  local candidate
  candidate=$(mktemp)
  jq -n '{
    "$schema": "https://sing-box.sagernet.org/schema.json",
    log: { level: "info", timestamp: true },
    inbounds: [],
    outbounds: [
      { type: "direct", tag: "direct" },
      { type: "block", tag: "block" }
    ],
    route: { final: "direct" }
  }' > "$candidate"
  install -m 600 "$candidate" "$CONFIG_FILE"
  rm -f "$candidate"
}

backup_config() {
  [[ -f $CONFIG_FILE ]] || return
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  install -m 600 "$CONFIG_FILE" "${BACKUP_DIR}/config-${stamp}.json"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'config-*.json' -printf '%T@ %p\n' \
    | sort -nr | awk 'NR>10 {print $2}' | xargs -r rm -f
}

validate_candidate() {
  local candidate=$1
  sing-box check -c "$candidate"
}

apply_candidate() {
  local candidate=$1
  validate_candidate "$candidate"
  backup_config
  install -m 600 "$candidate" "$CONFIG_FILE"
  systemctl enable --now sing-box
  systemctl restart sing-box
}

port_is_used_in_config() {
  local port=$1
  jq -e --argjson port "$port" '.inbounds[]? | select(.listen_port == $port)' "$CONFIG_FILE" >/dev/null
}

ensure_port_available() {
  local port=$1
  if port_is_used_in_config "$port"; then
    die "端口 $port 已在 sing-box 配置中使用。"
  fi
  if ss -ltnu 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]${port}$"; then
    die "端口 $port 已被其他进程监听，请换一个端口。"
  fi
}

open_firewall_port() {
  local port=$1 protocol=${2:-tcp}
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'Status: active'; then
    ufw allow "${port}/${protocol}" >/dev/null
    ok "已通过 UFW 放行 ${port}/${protocol}"
  else
    warn "未检测到启用中的 UFW；请同时在云厂商安全组放行 ${port}/${protocol}。"
  fi
}

random_ss_key() {
  sing-box generate rand --base64 16 2>/dev/null || openssl rand -base64 16 | tr -d '\n'
}

random_token() {
  openssl rand -hex 24
}

new_uuid() {
  sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
}

save_connection() {
  local type=$1 tag=$2 host=$3 port=$4 uri=$5
  local candidate
  candidate=$(mktemp)
  jq --arg type "$type" --arg tag "$tag" --arg host "$host" --argjson port "$port" --arg uri "$uri" \
    '.connections += [{type:$type, tag:$tag, host:$host, port:$port, uri:$uri, created_at:(now|strftime("%Y-%m-%dT%H:%M:%SZ"))}]' \
    "$STATE_FILE" > "$candidate"
  install -m 600 "$candidate" "$STATE_FILE"
  rm -f "$candidate"
}

tls_json() {
  local domain=$1 cert=$2 key=$3
  jq -n --arg domain "$domain" --arg cert "$cert" --arg key "$key" \
    '{enabled:true,server_name:$domain,alpn:["h2","http/1.1"],min_version:"1.2",certificate_path:$cert,key_path:$key}'
}

install_certbot_hook() {
  install -d -m 755 "$(dirname "$CERT_HOOK")"
  tee "$CERT_HOOK" >/dev/null <<'EOF'
#!/usr/bin/env bash
systemctl try-restart sing-box.service
EOF
  chmod 755 "$CERT_HOOK"
}

obtain_tls_paths() {
  local domain=$1 cert key choice
  cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
  key="/etc/letsencrypt/live/${domain}/privkey.pem"
  if [[ -r $cert && -r $key ]]; then
    printf '%s|%s' "$cert" "$key"
    return
  fi
  printf "\nTLS 证书方式：\n  1) 使用 Certbot / Let's Encrypt 自动签发（需域名已解析到本机，80/TCP 可访问）\n  2) 使用已有 PEM 证书\n"
  read -r -p '选择 [1]: ' choice
  choice=${choice:-1}
  case $choice in
    1)
      apt-get update >&2
      apt-get install -y certbot >&2
      open_firewall_port 80 tcp >&2
      info "正在申请 ${domain} 的证书" >&2
      certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain" >&2
      install_certbot_hook
      [[ -r $cert && -r $key ]] || die "证书文件没有生成。"
      ;;
    2)
      cert=$(ask_required "证书链 PEM 的绝对路径")
      key=$(ask_required "私钥 PEM 的绝对路径")
      [[ -r $cert && -r $key ]] || die "证书或私钥不可读。"
      ;;
    *) die "无效选择。" ;;
  esac
  printf '%s|%s' "$cert" "$key"
}

deploy_shadowsocks() {
  ensure_installed
  create_base_config
  local port host key tag inbound encoded uri candidate
  port=$(ask_port "Shadowsocks 2022 监听端口" 8443)
  ensure_port_available "$port"
  host=$(ask_server_address)
  key=$(random_ss_key)
  tag="ss2022-${port}"
  inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg key "$key" \
    '{type:"shadowsocks",tag:$tag,listen:"::",listen_port:$port,method:"2022-blake3-aes-128-gcm",password:$key,multiplex:{enabled:true}}')
  candidate=$(mktemp)
  jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE" > "$candidate"
  apply_candidate "$candidate"
  rm -f "$candidate"
  encoded=$(printf '%s' "2022-blake3-aes-128-gcm:${key}" | base64 -w 0)
  uri="ss://${encoded}@${host}:${port}#sing-box-SS2022-${port}"
  save_connection "shadowsocks-2022" "$tag" "$host" "$port" "$uri"
  open_firewall_port "$port" tcp
  open_firewall_port "$port" udp
  ok "Shadowsocks 2022 已部署"
  printf '\n客户端连接串：\n%s\n\n' "$uri"
}

deploy_trojan() {
  ensure_installed
  create_base_config
  local domain port paths cert key password tag tls inbound candidate uri
  domain=$(ask_required "TLS 域名")
  valid_hostname "$domain" || die "域名格式不正确。"
  port=$(ask_port "Trojan 监听端口" 443)
  ensure_port_available "$port"
  paths=$(obtain_tls_paths "$domain")
  cert=${paths%%|*}
  key=${paths#*|}
  password=$(random_token)
  tag="trojan-${port}"
  tls=$(tls_json "$domain" "$cert" "$key")
  inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg password "$password" --argjson tls "$tls" \
    '{type:"trojan",tag:$tag,listen:"::",listen_port:$port,users:[{name:"default",password:$password}],tls:$tls}')
  candidate=$(mktemp)
  jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE" > "$candidate"
  apply_candidate "$candidate"
  rm -f "$candidate"
  uri="trojan://${password}@${domain}:${port}?security=tls&sni=${domain}&type=tcp#sing-box-Trojan-${port}"
  save_connection "trojan-tls" "$tag" "$domain" "$port" "$uri"
  open_firewall_port "$port" tcp
  ok "Trojan TLS 已部署"
  printf '\n客户端连接串：\n%s\n\n' "$uri"
}

deploy_vless() {
  ensure_installed
  create_base_config
  local domain port paths cert key uuid tag tls inbound candidate uri
  domain=$(ask_required "TLS 域名")
  valid_hostname "$domain" || die "域名格式不正确。"
  port=$(ask_port "VLESS 监听端口" 8443)
  ensure_port_available "$port"
  paths=$(obtain_tls_paths "$domain")
  cert=${paths%%|*}
  key=${paths#*|}
  uuid=$(new_uuid)
  tag="vless-${port}"
  tls=$(tls_json "$domain" "$cert" "$key")
  inbound=$(jq -n --arg tag "$tag" --argjson port "$port" --arg uuid "$uuid" --argjson tls "$tls" \
    '{type:"vless",tag:$tag,listen:"::",listen_port:$port,users:[{name:"default",uuid:$uuid}],tls:$tls}')
  candidate=$(mktemp)
  jq --argjson inbound "$inbound" '.inbounds += [$inbound]' "$CONFIG_FILE" > "$candidate"
  apply_candidate "$candidate"
  rm -f "$candidate"
  uri="vless://${uuid}@${domain}:${port}?encryption=none&security=tls&type=tcp&sni=${domain}#sing-box-VLESS-${port}"
  save_connection "vless-tls" "$tag" "$domain" "$port" "$uri"
  open_firewall_port "$port" tcp
  ok "VLESS TLS 已部署"
  printf '\n客户端连接串：\n%s\n\n' "$uri"
}

show_connections() {
  ensure_dirs
  if [[ $(jq '.connections | length' "$STATE_FILE") -eq 0 ]]; then
    warn "尚未由本脚本创建连接。"
    return
  fi
  printf '\n已保存的客户端连接串（请妥善保管）：\n\n'
  jq -r '.connections[] | "[\(.type)] \(.tag)  \(.host):\(.port)\n\(.uri)\n"' "$STATE_FILE"
}

list_inbounds() {
  create_base_config
  jq -r '.inbounds | to_entries[] | "\(.key + 1). \(.value.tag) [\(.value.type)] :\(.value.listen_port)"' "$CONFIG_FILE"
}

remove_inbound() {
  ensure_installed
  create_base_config
  local tag candidate
  if [[ $(jq '.inbounds | length' "$CONFIG_FILE") -eq 0 ]]; then
    warn "当前没有入站。"
    return
  fi
  printf '\n当前入站：\n'
  list_inbounds
  tag=$(ask_required "输入要删除的 tag")
  jq -e --arg tag "$tag" '.inbounds[] | select(.tag == $tag)' "$CONFIG_FILE" >/dev/null || die "未找到该 tag。"
  confirm "确认删除 ${tag}" N || return
  candidate=$(mktemp)
  jq --arg tag "$tag" '.inbounds |= map(select(.tag != $tag))' "$CONFIG_FILE" > "$candidate"
  apply_candidate "$candidate"
  rm -f "$candidate"
  candidate=$(mktemp)
  jq --arg tag "$tag" '.connections |= map(select(.tag != $tag))' "$STATE_FILE" > "$candidate"
  install -m 600 "$candidate" "$STATE_FILE"
  rm -f "$candidate"
  ok "已删除 ${tag}"
}

validate_and_restart() {
  ensure_installed
  sing-box check -c "$CONFIG_FILE"
  systemctl enable --now sing-box
  systemctl restart sing-box
  ok "配置校验通过，服务已重启。"
}

show_status() {
  ensure_installed
  printf '\nsing-box: '
  sing-box version | head -n 1
  printf '\n服务状态：\n'
  systemctl --no-pager --full status sing-box || true
  printf '\n已配置的入站：\n'
  if [[ -f $CONFIG_FILE ]]; then
    jq -r '.inbounds[]? | "- \(.tag) [\(.type)] 监听 \(.listen):\(.listen_port)"' "$CONFIG_FILE"
  fi
}

show_logs() {
  journalctl -u sing-box -n 120 --no-pager -o cat
}

upgrade_sing_box() {
  ensure_installed
  info "更新 sing-box 官方软件包"
  apt-get update
  apt-get install -y --only-upgrade sing-box
  validate_and_restart
  ok "更新完成：$(sing-box version | head -n 1)"
}

enable_bbr() {
  require_root
  local sysctl_file="/etc/sysctl.d/99-sing-box-bbr.conf"
  tee "$sysctl_file" >/dev/null <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null
  ok "已写入 BBR 设置；当前算法：$(sysctl -n net.ipv4.tcp_congestion_control)"
}

restore_backup() {
  ensure_installed
  local file candidate
  file=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'config-*.json' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
  [[ -n $file ]] || die "没有可用备份。"
  warn "将恢复最近备份：$file"
  confirm "确认恢复" N || return
  candidate=$(mktemp)
  install -m 600 "$file" "$candidate"
  apply_candidate "$candidate"
  rm -f "$candidate"
  ok "已恢复最近备份。"
}

uninstall_sing_box() {
  require_root
  warn "这会停止并卸载 sing-box 软件包；配置和连接记录会保留在本机，便于恢复。"
  confirm "确认卸载" N || return
  systemctl disable --now sing-box 2>/dev/null || true
  apt-get remove -y sing-box
  ok "sing-box 已卸载；保留目录：${CONFIG_DIR}、${STATE_DIR}"
}

print_menu() {
  printf '\n%s\n' '========================================'
  printf ' sing-box VPS 一键部署 v%s\n' "$SCRIPT_VERSION"
  printf '%s\n' '========================================'
  printf '1) 安装 / 修复官方 sing-box\n'
  printf '2) 新建 Shadowsocks 2022 入站\n'
  printf '3) 新建 Trojan + TLS 入站\n'
  printf '4) 新建 VLESS + TLS 入站\n'
  printf '5) 查看客户端连接串\n'
  printf '6) 删除入站\n'
  printf '7) 校验配置并重启\n'
  printf '8) 查看服务状态\n'
  printf '9) 查看最近日志\n'
  printf '10) 更新 sing-box\n'
  printf '11) 启用 BBR\n'
  printf '12) 恢复最近配置备份\n'
  printf '13) 卸载 sing-box（保留配置）\n'
  printf '0) 退出\n\n'
}

menu() {
  local choice
  while true; do
    print_menu
    read -r -p '请选择: ' choice
    case $choice in
      1) install_sing_box ;;
      2) deploy_shadowsocks ;;
      3) deploy_trojan ;;
      4) deploy_vless ;;
      5) show_connections ;;
      6) remove_inbound ;;
      7) validate_and_restart ;;
      8) show_status ;;
      9) show_logs ;;
      10) upgrade_sing_box ;;
      11) enable_bbr ;;
      12) restore_backup ;;
      13) uninstall_sing_box ;;
      0) exit 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

usage() {
  printf '用法：sudo bash %s [menu|install|ss|trojan|vless|status|links|check|logs|upgrade|bbr|rollback|remove|uninstall]\n' "$0"
}

main() {
  case ${1:-menu} in
    -h|--help|help) usage; return ;;
  esac
  require_root
  case ${1:-menu} in
    menu) menu ;;
    install) install_sing_box ;;
    ss) deploy_shadowsocks ;;
    trojan) deploy_trojan ;;
    vless) deploy_vless ;;
    status) show_status ;;
    links) show_connections ;;
    check) validate_and_restart ;;
    logs) show_logs ;;
    upgrade) upgrade_sing_box ;;
    bbr) enable_bbr ;;
    rollback) restore_backup ;;
    remove) remove_inbound ;;
    uninstall) uninstall_sing_box ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
