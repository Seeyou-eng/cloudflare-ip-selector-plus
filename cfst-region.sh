#!/usr/bin/env bash
# ============================================================
#  cfst-region.sh — Cloudflare 优选 IP（XIU2 引擎 + 地区筛选）
#
#  合并优点：
#   - XIU2/CloudflareSpeedTest v2.3.5：核心测速引擎，延迟测速准确
#   - chitongx/cloudflare-ip-selector：按地区筛选、桌面归档、
#     干净可复制格式 IP:端口#地区码，延迟+下载双指标
#
#  针对 2026-11-10 实测问题的修复：
#   1. cf.xiu2.xyz/url 已失效（403），不用
#   2. cfst 自带下载用大文件（300MB）HTTPS 在厦门电信报 403，
#      改为 curl 小文件补测：先 HTTPS 2MB，403/0 再试 HTTP 50MB
#      （80 端口，绕 SNI 阻断）
#   3. cfst 的 -httping 模式在部分网络下可用 IP 为 0（本机 Linux
#      实测），改用 TCP 延迟测速（最稳）+ curl 补测
#  2026-11-11 对比其他项目后的改进（CloudFlareScan / ip-optimizer）：
#   4. 地区码改用 /cdn-cgi/trace 拿（几百字节），不用下 2MB 再从
#      响应头里抠 colo:，轻、快、不吃 403
#   5. 先用 /__down?bytes=0 预检（流量为 0），通了再下真的文件，
#      失败原因分得清：预检不通是连通性问题，下载 0 是测速地址问题
#
#  用法：
#    ./cfst-region.sh                      # 默认 SIN,NRT,HKG，每地区 Top 4
#    ./cfst-region.sh "SIN,NRT"            # 只测指定地区
#    ./cfst-region.sh "SIN,NRT" 6          # 指定地区 + 每地区取 6 个
#
#  输出（Mac：~/Desktop/Cloudflare优选IP/；Linux：~/Cloudflare优选IP/）：
#    最优IP-汇总.txt / 全部结果.csv / SIN-新加坡.txt 等每地区一个文件
#  每行格式：IP:443#新加坡 🇸🇬 62ms
#    行首一定是数字 IP；国旗只能放 # 后面的备注里，放 IP 前面会失效
#    延迟 200ms 以上不要；下载速度仍记在 全部结果.csv 里，不放在 txt 行里
#
#  依赖：同目录下的 cfst（v2.3.5）+ ip.txt，curl、python3
#  测速前请先退出代理软件（Hiddify 等），否则延迟会失真
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

CFST_BIN="./cfst"
# 补测下载：先 HTTPS 2MB，失败再 HTTP 50MB
DL_URL_HTTPS="https://speed.cloudflare.com/__down?bytes=2000000"
DL_URL_HTTP="http://speed.cloudflare.com/__down?bytes=50000000"

COLOS="${1:-SIN,NRT,HKG}"
TOP_N="${2:-4}"
PORT=443
if [ "$(uname -s)" = "Darwin" ]; then
  OUT_DIR="${HOME}/Desktop/Cloudflare优选IP"
else
  OUT_DIR="${HOME}/Cloudflare优选IP"
fi
# 先按延迟取多少个候选，再用 curl 拿地区码 + 下载速度
CANDIDATES="${CANDIDATES:-30}"

mkdir -p "$OUT_DIR"

echo "==> [1/2] TCP 延迟测速中（每地区 Top ${TOP_N}，延迟上限 200ms）..."
# TCP 模式最稳；-dd 跳过 cfst 自带下载（403 重灾区，改用 curl 补测）
if ! "$CFST_BIN" -dd -tl 200 -tlr 0.2 -n 100 -o result.csv; then
  echo "!! CFST 延迟测速失败" >&2
  exit 1
fi
if [ ! -f result.csv ]; then
  echo "!! 未生成 result.csv，延迟测速可用 IP 为 0，请检查网络或代理是否已退出" >&2
  exit 1
fi

echo "==> [2/2] 为延迟最低的 ${CANDIDATES} 个 IP 补测地区码 + 下载速度（trace 拿地区 + bytes=0 预检 + 下载）..."
COLOS="$COLOS" TOP_N="$TOP_N" PORT="$PORT" OUT_DIR="$OUT_DIR" \
CANDIDATES="$CANDIDATES" DL_URL_HTTPS="$DL_URL_HTTPS" DL_URL_HTTP="$DL_URL_HTTP" \
env -u PYTHONPATH python3 << 'PYEOF'
import csv, os, collections, datetime, subprocess, re

colo_csv = os.environ["COLOS"]
top_n = int(os.environ["TOP_N"])
port = os.environ["PORT"]
out_dir = os.environ["OUT_DIR"]
candidates_n = int(os.environ["CANDIDATES"])
dl_https = os.environ["DL_URL_HTTPS"]
dl_http = os.environ["DL_URL_HTTP"]

# 地区码 -> (国家名, 国旗)，国旗只放 # 后面，绝不放 IP 前面
COUNTRY = {
    "SIN": ("新加坡", "🇸🇬"), "NRT": ("日本", "🇯🇵"),
    "HKG": ("香港", "🇭🇰"), "TPE": ("台湾", "🇹🇼"), "KHH": ("台湾", "🇹🇼"),
    "ICN": ("韩国", "🇰🇷"), "LAX": ("美国", "🇺🇸"), "SJC": ("美国", "🇺🇸"),
    "SEA": ("美国", "🇺🇸"), "FRA": ("德国", "🇩🇪"),
    "ORD": ("美国", "🇺🇸"), "DFW": ("美国", "🇺🇸"), "ATL": ("美国", "🇺🇸"),
    "DEN": ("美国", "🇺🇸"), "EWR": ("美国", "🇺🇸"), "MIA": ("美国", "🇺🇸"),
}
REGION_NAMES = {
    "HKG": "香港", "NRT": "日本", "KHH": "台湾", "TPE": "台湾", "SIN": "新加坡",
    "ICN": "韩国", "LAX": "美国", "SJC": "美国", "SEA": "美国", "FRA": "德国",
    "ORD": "美国", "DFW": "美国", "ATL": "美国",
}
requested = [c.strip().upper() for c in colo_csv.split(",") if c.strip()]

with open("result.csv", newline='', encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))

# 按延迟从低到高取候选（已在 cfst 里过滤了 200ms / 丢包）
cands = []
for r in rows:
    try:
        lat = float(r.get("平均延迟") or 9999)
    except ValueError:
        continue
    if lat > 200:
        continue
    cands.append((lat, (r.get("IP 地址") or "").strip()))
cands = sorted(cands)[:candidates_n]
if not cands:
    print("!! 延迟 200ms 内无可用 IP")
    raise SystemExit(1)

def get_colo(ip):
    """用 /cdn-cgi/trace 拿地区码，几百字节，不用下载。
    先 HTTPS 443，失败再试 HTTP 80，解析回包里的 colo=XXX。"""
    for scheme, resolve_port in (("https", 443), ("http", 80)):
        try:
            r = subprocess.run(
                ["curl", "-s", "--max-time", "5",
                 "--resolve", f"speed.cloudflare.com:{resolve_port}:{ip}",
                 f"{scheme}://speed.cloudflare.com/cdn-cgi/trace"],
                capture_output=True, text=True, timeout=8)
            m = re.search(r"(?m)^colo=([A-Z]{3})\s*$", r.stdout or "")
            if m:
                return m.group(1)
        except Exception:
            continue
    return "N/A"

def precheck(ip):
    """用 /__down?bytes=0 预检，流量为 0，只验 HTTP 层通不通。
    先 HTTPS，失败再试 HTTP，返回 True/False。"""
    for scheme, resolve_port in (("https", 443), ("http", 80)):
        try:
            r = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "--max-time", "5",
                 "--resolve", f"speed.cloudflare.com:{resolve_port}:{ip}",
                 f"{scheme}://speed.cloudflare.com/__down?bytes=0"],
                capture_output=True, text=True, timeout=8)
            if (r.stdout or "").strip() == "200":
                return True
        except Exception:
            continue
    return False

def download_mbps(ip):
    """下载测速：先 HTTPS 2MB，403/0 再试 HTTP 50MB，返回 Mbps。"""
    for url, resolve_port in ((dl_https, 443), (dl_http, 80)):
        try:
            r = subprocess.run(
                ["curl", "-s", "-o", "/dev/null",
                 "-w", "%{http_code} %{speed_download}",
                 "--max-time", "12",
                 "--resolve", f"speed.cloudflare.com:{resolve_port}:{ip}", url],
                capture_output=True, text=True, timeout=17)
            parts = (r.stdout or "").strip().split()
            if len(parts) >= 2 and parts[0] == "200":
                return float(parts[1]) * 8 / 1_000_000
        except Exception:
            continue
    return 0.0

def probe(ip):
    """三步：trace 拿地区码 -> bytes=0 预检 -> 下载测速。
    返回 (colo, mbps, 方法)。"""
    colo = get_colo(ip)
    if not precheck(ip):
        return colo, 0.0, "precheck-fail"
    mbps = download_mbps(ip)
    return colo, mbps, "ok"

from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(max_workers=10) as ex:
    probed = list(ex.map(lambda c: probe(c[1]), cands))

# 按地区分组
groups = collections.defaultdict(list)
for (lat, ip), (colo, mbps, _method) in zip(cands, probed):
    groups[colo].append((lat, ip, mbps))

date_str = datetime.date.today().strftime("%Y-%m-%d")
lines = [f"Cloudflare 优选 IP（{date_str}）", "=" * 60]

for colo in requested:
    name = REGION_NAMES.get(colo, colo)
    country, flag = COUNTRY.get(colo, (name, ""))
    if colo not in groups:
        lines.append(f"# {colo}（{name}）: 本轮未测到可用 IP")
        continue
    top = sorted(groups[colo], key=lambda x: x[0])[:top_n]
    lines.append(f"# {colo}（{name}）:")
    with open(os.path.join(out_dir, f"{colo}-{name}.txt"), "w", encoding="utf-8") as f:
        f.write(f"# {colo}（{name}）Cloudflare 优选 IP Top{len(top)}（{date_str}）\n")
        for lat, ip, mbps in top:
            line = f"{ip}:{port}#{country} {flag} {lat:.0f}ms"
            lines.append(line)
            f.write(line + "\n")

# 其余地区（不在请求列表里的）也汇总到文件末尾，方便参考
extra = [c for c in groups if c not in requested and c != "N/A"]
if extra:
    lines.append("# 其他地区（本轮测到，供参考）:")
    for colo in sorted(extra):
        country, flag = COUNTRY.get(colo, (colo, ""))
        for lat, ip, mbps in sorted(groups[colo], key=lambda x: x[0])[:2]:
            lines.append(f"{ip}:{port}#{country} {flag} {lat:.0f}ms")

with open(os.path.join(out_dir, "最优IP-汇总.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

with open(os.path.join(out_dir, "全部结果.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["IP地址", "平均延迟(ms)", "下载速度(Mbps)", "地区码"])
    for (lat, ip), (colo, mbps, _m) in zip(cands, probed):
        w.writerow([ip, f"{lat:.2f}", f"{mbps:.2f}", colo])

print("\n".join(lines))
print(f"\n✅ 已更新: {out_dir}")
print("   说明：地区码来自 /cdn-cgi/trace，下载速度记在 全部结果.csv 里；预检不通的下载记为 0，若下载全为 0，说明测速地址仍被拦，请换时间或换网络再测")
PYEOF
echo "==> 完成"
