# sing-box VPS 一键部署脚本

这是一个面向 Debian/Ubuntu VPS 的交互式部署脚本。它使用 sing-box 官方 APT 软件源，并按照官方配置文档生成 JSON 配置。

## 快速开始

将 [sing-box-vps.sh](./sing-box-vps.sh) 上传到 VPS 后执行：

```bash
chmod +x sing-box-vps.sh
sudo ./sing-box-vps.sh
```

脚本会显示交互菜单。建议先选择 `1` 安装官方 sing-box，再选择 `2`、`3` 或 `4` 创建入站。

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
| 5 | 导出本脚本创建过的连接串。 |
| 6 | 按 tag 删除一个入站和对应保存的连接信息。 |
| 7 | 使用 `sing-box check` 校验后重启服务。 |
| 8、9 | 查看 systemd 服务状态和最近 120 行日志。 |
| 10 | 从官方 APT 源升级 sing-box，并校验、重启。 |
| 11 | 写入并应用 BBR sysctl 配置。 |
| 12 | 恢复最近一份自动配置备份。 |
| 13 | 停止并卸载软件包，但保留配置与连接记录。 |

## 非交互命令

| 命令 | 作用 |
| --- | --- |
| `sudo ./sing-box-vps.sh install` | 安装官方软件包。 |
| `sudo ./sing-box-vps.sh ss` | 进入 Shadowsocks 2022 创建流程。 |
| `sudo ./sing-box-vps.sh trojan` | 进入 Trojan TLS 创建流程。 |
| `sudo ./sing-box-vps.sh vless` | 进入 VLESS TLS 创建流程。 |
| `sudo ./sing-box-vps.sh status` | 查看运行状态。 |
| `sudo ./sing-box-vps.sh links` | 输出保存的连接串。 |
| `sudo ./sing-box-vps.sh check` | 校验配置并重启。 |
| `sudo ./sing-box-vps.sh upgrade` | 升级 sing-box。 |
| `sudo ./sing-box-vps.sh rollback` | 恢复最近备份。 |

## 功能

- 安装和更新官方 sing-box 软件包，配置官方签名 APT 源。
- 新建多个 Shadowsocks 2022、Trojan TLS、VLESS TLS 入站。
- Trojan/VLESS 可自动经 Certbot 申请 Let's Encrypt 证书，或使用已有 PEM 证书；续期后自动重启 sing-box。
- 每次写入前执行 `sing-box check`，成功后才替换配置；自动保留最近 10 份备份并可一键恢复。
- 将连接信息保存到仅 root 可读的状态文件，菜单可再次导出连接串。
- 集成 UFW 放行提示、服务状态、日志、升级、BBR、删除入站和保守卸载。

## 使用前检查

- 使用 root 或 `sudo` 运行，系统须为带 systemd 的 Debian/Ubuntu。
- 在云厂商安全组中放行你选择的端口；如果用 Certbot 自动证书，还要放行 `80/TCP`，并让域名 A/AAAA 记录指向该 VPS。
- 脚本会尝试给已启用的 UFW 放行端口，但无法替你修改云厂商安全组。
- 连接串含密钥，请只在可信设备之间传递。请遵守所在地法律、网络与服务商规则。

## 官方资料

- [Package Manager](https://sing-box.sagernet.org/installation/package-manager/)
- [Shadowsocks Inbound](https://sing-box.sagernet.org/configuration/inbound/shadowsocks/)
- [Trojan Inbound](https://sing-box.sagernet.org/configuration/inbound/trojan/)
- [VLESS Inbound](https://sing-box.sagernet.org/configuration/inbound/vless/)
- [TLS](https://sing-box.sagernet.org/configuration/shared/tls/)
