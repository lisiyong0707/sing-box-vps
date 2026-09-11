# sing-box VPS 一键部署脚本

这是一个面向 Debian/Ubuntu VPS 的交互式部署脚本。它使用 sing-box 官方 APT 软件源，并按照官方配置文档生成 JSON 配置。

## 快速开始

将 [sing-box-vps.sh](./sing-box-vps.sh) 上传到 VPS 后执行：

```bash
chmod +x sing-box-vps.sh
sudo ./sing-box-vps.sh
```

脚本会显示交互菜单。建议先选择 `1` 安装官方 sing-box，再选择 `2`、`3` 或 `4` 创建入站。

安装完成后，脚本会复制自身到 `/usr/local/sbin/sing-box-vps` 并创建全局快捷命令 `sb`。以后 SSH 登录 VPS 后，直接运行：

```bash
sudo sb
```

也可以直达常用运维操作：

```bash
sudo sb status
sudo sb health
sudo sb certs
sudo sb logs
sudo sb self-update
```

## GitHub 与 SSH 一键部署

可以将脚本放进你自己的 GitHub 仓库。假设仓库名为 `YOUR_GITHUB_USER/sing-box-vps`，且脚本位于仓库根目录：

```bash
git init
git add sing-box-vps.sh README.md
git commit -m "Add sing-box VPS deployer"
git branch -M main
git remote add origin git@github.com:YOUR_GITHUB_USER/sing-box-vps.git
git push -u origin main
```

首次安装可从本地电脑通过 SSH 执行。替换仓库名和 VPS 地址：

```bash
ssh -t root@YOUR_VPS_IP 'curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/sing-box-vps/main/sing-box-vps.sh -o /tmp/sing-box-vps.sh && bash /tmp/sing-box-vps.sh'
```

若 VPS 禁止 root 直接 SSH，使用普通 sudo 用户：

```bash
ssh -t YOUR_USER@YOUR_VPS_IP 'curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/sing-box-vps/main/sing-box-vps.sh -o /tmp/sing-box-vps.sh && sudo bash /tmp/sing-box-vps.sh'
```

`-t` 会保留交互终端，因此可以在本地直接操作脚本菜单。为避免下载内容被替换，建议使用 GitHub Release 固定版本 URL，或在执行前校验发布的 SHA-256。

也可以直接进入指定功能，例如：

```bash
sudo ./sing-box-vps.sh install
sudo ./sing-box-vps.sh ss
sudo ./sing-box-vps.sh trojan
sudo ./sing-box-vps.sh vless
sudo ./sing-box-vps.sh status
```

## 菜单功能

| 菜单 | 用途 |
| --- | --- |
| 1 | 写入官方签名 APT 源并安装/修复 sing-box。 |
| 2 | 新建 Shadowsocks 2022 入站，同时生成并保存连接串。 |
| 3 | 新建 Trojan TCP + TLS 入站，可签发或导入证书。 |
| 4 | 新建 VLESS TCP + TLS 入站，可签发或导入证书。 |
| 5、6、7 | 分别新建 Hysteria2 TLS、TUIC TLS、VLESS Reality 入站。 |
| 8、9 | 导出连接串或按 tag 删除入站。 |
| 10、11、12 | 校验重启、查看状态及公网 IP、查看日志。 |
| 13、14、15、16 | 升级、启用 BBR、恢复最近备份、卸载 sing-box。 |
| 17、18 | 配置 Cloudflare Tunnel + VLESS WebSocket，或查看 `cloudflared` 状态。 |
| 19、20 | 运行健康检查，或查看 TLS 证书到期时间。 |
| 21、22 | 安装/修复 `sb` 快捷命令，或从你的 GitHub 仓库更新管理脚本。 |

## 非交互命令

| 命令 | 作用 |
| --- | --- |
| `sudo ./sing-box-vps.sh install` | 安装官方软件包。 |
| `sudo ./sing-box-vps.sh ss` | 进入 Shadowsocks 2022 创建流程。 |
| `sudo ./sing-box-vps.sh trojan` | 进入 Trojan TLS 创建流程。 |
| `sudo ./sing-box-vps.sh vless` | 进入 VLESS TLS 创建流程。 |
| `sudo ./sing-box-vps.sh hy2` | 进入 Hysteria2 TLS 创建流程。 |
| `sudo ./sing-box-vps.sh tuic` | 进入 TUIC TLS 创建流程。 |
| `sudo ./sing-box-vps.sh reality` | 进入 VLESS Reality 创建流程。 |
| `sudo ./sing-box-vps.sh status` | 查看运行状态。 |
| `sudo ./sing-box-vps.sh links` | 输出保存的连接串。 |
| `sudo ./sing-box-vps.sh check` | 校验配置并重启。 |
| `sudo ./sing-box-vps.sh upgrade` | 升级 sing-box。 |
| `sudo ./sing-box-vps.sh rollback` | 恢复最近备份。 |
| `sudo ./sing-box-vps.sh cftunnel` | 配置 Cloudflare Tunnel + VLESS WebSocket。 |
| `sudo ./sing-box-vps.sh cfstatus` | 查看 Cloudflare Tunnel 服务状态。 |
| `sudo ./sing-box-vps.sh health` | 检查配置、服务与监听端口。 |
| `sudo ./sing-box-vps.sh certs` | 查看所有文件证书的到期时间。 |
| `sudo ./sing-box-vps.sh self-update` | 下载并校验你的 GitHub 仓库中的最新版脚本。 |

## 功能

- 安装和更新官方 sing-box 软件包，配置官方签名 APT 源。
- 新建多个 Shadowsocks 2022、Trojan TLS、VLESS TLS、Hysteria2 TLS、TUIC TLS、VLESS Reality 入站。
- Trojan/VLESS 可自动经 Certbot 申请 Let's Encrypt 证书，或使用已有 PEM 证书；续期后自动重启 sing-box。
- 可选 Cloudflare Tunnel：部署本地 VLESS WebSocket 入站，并使用 Cloudflare 的远程管理 Tunnel 公开域名。
- 自动检测公网 IPv4/IPv6；Hysteria2、TUIC 会自动放行对应 UDP 端口。
- 每次写入前执行 `sing-box check`，成功后才替换配置；自动保留最近 10 份备份并可一键恢复。
- 将连接信息保存到仅 root 可读的状态文件，菜单可再次导出连接串。
- 集成 UFW 放行提示、服务状态、日志、升级、BBR、删除入站和保守卸载。
- 提供 `sb` 全局快捷命令、健康检查、证书到期检查和管理脚本自更新。

## 使用前检查

- 使用 root 或 `sudo` 运行，系统须为带 systemd 的 Debian/Ubuntu。
- 在云厂商安全组中放行你选择的端口；如果用 Certbot 自动证书，还要放行 `80/TCP`，并让域名 A/AAAA 记录指向该 VPS。
- 脚本会尝试给已启用的 UFW 放行端口，但无法替你修改云厂商安全组。
- 连接串含密钥，请只在可信设备之间传递。请遵守所在地法律、网络与服务商规则。

## Cloudflare Tunnel

此功能使用 Cloudflare 官方 `cloudflared` APT 源和远程管理 Tunnel，不使用临时 `trycloudflare.com` 域名。使用前，请在 Cloudflare Zero Trust 的 **Networking > Tunnels** 创建 Tunnel，并为它添加一个 Published application：

```text
Hostname: 你的子域名，例如 cf.example.com
Service URL: http://127.0.0.1:脚本显示的本地端口
```

在 Tunnel 的 **Add a replica** 页面复制 Token，脚本会隐藏输入并只交给 `cloudflared service install`，不会写入连接记录或显示在终端。Token 等同于运行该 Tunnel 的权限；若怀疑泄露，请在 Cloudflare 后台立即轮换。Cloudflare 的公网 Hostname 路由面向 HTTP/WebSocket；脚本因此创建 VLESS WebSocket 入站，而不把 Trojan、Shadowsocks 或 Hysteria2 的原始 TCP/UDP 直接放到 Tunnel 中。

## 官方资料

- [Package Manager](https://sing-box.sagernet.org/installation/package-manager/)
- [Shadowsocks Inbound](https://sing-box.sagernet.org/configuration/inbound/shadowsocks/)
- [Trojan Inbound](https://sing-box.sagernet.org/configuration/inbound/trojan/)
- [VLESS Inbound](https://sing-box.sagernet.org/configuration/inbound/vless/)
- [TLS](https://sing-box.sagernet.org/configuration/shared/tls/)
- [Cloudflare Tunnel Setup](https://developers.cloudflare.com/tunnel/setup/)
- [Cloudflare Tunnel Tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/)
