# Cloudflare 优选 IP（XIU2 引擎 + 地区筛选）

按地区筛选 Cloudflare 最优 IP，延迟 + 下载双指标，输出可直接复制的优选列表。

> 合并了两个项目的优点：XIU2 的测速引擎 + chitongx 的地区筛选和桌面归档，并修复了 2026-11-10 实测的下载测速 403 问题。

## 优点取自哪里

**取自 XIU2/CloudflareSpeedTest（★29,901，GPL-3.0，v2.3.5）：**
- 核心测速引擎，延迟测速准确，支持 `-httping` / `-debug` / `-cfcolo`
- 维护活跃，2026 年仍在更新

**取自 chitongx/cloudflare-ip-selector（MIT）：**
- 按地区筛选（SIN / NRT / HKG 等），每地区 Top N
- 输出格式 `IP:443#新加坡 🇸🇬 62ms`，行首一定是数字 IP，可直接复制；国旗只放 `#` 后面，放 IP 前面会失效
- 结果自动归档到桌面 `Cloudflare优选IP/` 文件夹：汇总 + 每地区一个文件 + 全量 CSV

**本次新增的修复（2026-11-10 厦门电信实测）：**
- 默认测速地址 `cf.xiu2.xyz/url` 已失效，返回 403，不再用
- `speed.cloudflare.com/__down?bytes=300000000` 的 HTTPS 大文件在当前网络下也返回 403
- 改用小文件 curl 补测下载：先试 HTTPS 2MB，403 / 0 速度时再试 HTTP 50MB（80 端口，绕 SNI 阻断）
- 延迟 200ms 以上直接过滤，下载为 0 的照实标注，不藏着

**2026-11-11 对比其他项目后的改进（CloudFlareScan / ip-optimizer）：**
- 地区码改用 `/cdn-cgi/trace` 拿（几百字节），不用下 2MB 再从响应头里抠 `colo:`，轻、快、不吃 403
- 先用 `/__down?bytes=0` 预检（流量为 0），通了再下真的文件，失败原因分得清
- 候选从 30 个提到 50 个，每段抽样从 100 个提到 200 个，基数大了更容易抓到更快的；默认仍测 SIN,NRT,HKG，不单独只测 HKG

## 快速开始（macOS Apple Silicon）

```bash
git clone https://github.com/Seeyou-eng/cloudflare-ip-selector-plus.git
cd cloudflare-ip-selector-plus
chmod +x install.sh cfst-region.sh   # GitHub 克隆后须先加执行权限
./install.sh        # 自动下载 cfst v2.3.5（Darwin arm64）
# 国内网络加速: MIRROR='https://ghfast.top/' ./install.sh
./cfst-region.sh    # 开始测速，约 5 分钟（候选 50 个，每段抽样 200 个）
```

## 用法

```bash
./cfst-region.sh                      # 默认 SIN,NRT,HKG，每地区 Top 4
./cfst-region.sh "SIN,NRT"            # 只测指定地区
./cfst-region.sh "SIN,NRT" 6          # 指定地区 + 每地区取 6 个
```

运行后自动更新桌面 `Cloudflare优选IP/` 文件夹：

| 文件 | 内容 |
| --- | --- |
| `最优IP-汇总.txt` | 全部地区优选列表（带日期） |
| `SIN-新加坡.txt` 等 | 每个地区独立文件 |
| `全部结果.csv` | 本次全量测速明细 |

输出示例：

```
Cloudflare 优选 IP（2026-11-10）
============================================================
# SIN（新加坡）:
162.159.44.220:443#新加坡 🇸🇬 62ms
162.159.32.242:443#新加坡 🇸🇬 63ms
```

## 测速前注意

- 测速前请先退出代理软件（Hiddify 等），否则延迟会失真，下载测速也可能失败
- 每次结果都不一样属正常：CFST 在每个 IP 段随机抽样，Cloudflare 路由也在动态变化
- HKG 等亚洲小众地区占比极低，随机抽样测不到属正常，建议优先用 SIN

## 测试记录

- 2026-11-10（厦门电信，Mac）：`cf.xiu2.xyz/url` 和 `https://speed.cloudflare.com/__down?bytes=300000000` 均报 HTTP 403，cfst 自带下载全为 0；`curl --resolve` 测 `https://speed.cloudflare.com/__down?bytes=2000000` 返回 200，`http://speed.cloudflare.com/__down?bytes=50000000` 返回 200。本项目据此改为 curl 小文件补测 + HTTP 兜底。
- 2026-11-10（本机 Linux，脚本逻辑跑通）：TCP 延迟测速 5955 个 IP 全部可用，curl 补测拿到地区码 + 下载速度 1.87-13.69 Mbps，输出 `最优IP-汇总.txt` / `全部结果.csv` 格式正确。因本机在美国，地区码为 ATL / DFW / LAX 等，SIN 未测到属正常；在厦门电信的 Mac 上应为 SIN / NRT，待用户在自己电脑上验证后为准。
- 2026-11-11（本机 Linux，新探针验证）：`/cdn-cgi/trace` 拿地区码通过（162.159.38.239 → DEN、104.18.35.43 → ORD、108.162.198.113 → MIA），`/__down?bytes=0` 预检全部通过，几百字节 + 0 流量，比原来下 2MB 拿地区码轻得多。

## 致谢

- [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) — 核心测速引擎（GPL-3.0）
- [chitongx/cloudflare-ip-selector](https://github.com/chitongx/cloudflare-ip-selector) — 地区筛选与桌面归档思路（MIT）

## License

本仓库的脚本（`install.sh` / `cfst-region.sh` / README）为 MIT License。`cfst` 二进制本身为 XIU2/CloudflareSpeedTest 的 GPL-3.0 作品，由 `install.sh` 在安装时从官方 Releases 下载，不随仓库分发。
