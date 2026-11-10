#!/usr/bin/env bash
# install.sh — 一键安装 Cloudflare 优选 IP 工具
# 自动下载对应平台的 CloudflareSpeedTest(cfst) v2.3.5 二进制
# 国内网络可用镜像加速: MIRROR='https://ghfast.top/' ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS-$ARCH" in
  Darwin-arm64)   ASSET=cfst_darwin_arm64.zip ;;
  Darwin-x86_64)  ASSET=cfst_darwin_amd64.zip ;;
  Linux-x86_64)   ASSET=cfst_linux_amd64.tar.gz ;;
  Linux-aarch64)  ASSET=cfst_linux_arm64.tar.gz ;;
  *) echo "!! 不支持的系统: $OS-$ARCH"; exit 1 ;;
esac

VERSION="${VERSION:-v2.3.5}"
MIRROR="${MIRROR:-}"
URL="${MIRROR}https://github.com/XIU2/CloudflareSpeedTest/releases/download/${VERSION}/${ASSET}"
echo "==> 下载 CloudflareSpeedTest ${VERSION}: ${ASSET}"
echo "    ${URL}"
if ! curl -sL --max-time 180 -o cfst_pkg "$URL"; then
  echo "!! 下载失败，国内网络可尝试: MIRROR='https://ghfast.top/' ./install.sh" >&2
  exit 1
fi

case "$ASSET" in
  *.zip)     unzip -o cfst_pkg && rm -f cfst_pkg ;;
  *.tar.gz)  tar -zxf cfst_pkg && rm -f cfst_pkg ;;
esac

chmod +x cfst cfst-region.sh 2>/dev/null || true
echo ""
echo "==> ✅ 安装完成！"
echo "    验证:  ./cfst -v"
echo "    用法:  ./cfst-region.sh              # 默认 SIN,NRT,HKG，每地区 Top 4"
echo "           ./cfst-region.sh \"SIN,NRT\" 6  # 指定地区 + 每地区取 6 个"
