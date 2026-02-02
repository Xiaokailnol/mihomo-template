#!/bin/sh
set -e

# ======================
# 基础信息
# ======================
REPO_OWNER="Xiaokailnol"
REPO_NAME="mihomo-template"
BIN_NAME="mihomo"

API_LATEST="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"

# ======================
# 日志工具
# ======================
info()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; exit 1; }

# ======================
# 参数解析
# ======================
DOWNLOAD_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      shift
      [ -z "$1" ] && error "Missing argument for --version"
      DOWNLOAD_VERSION="$1"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--version <version>]"
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
  esac
done

# ======================
# 系统检测
# ======================
detect_platform() {
  if command -v dpkg >/dev/null 2>&1; then
    PKG_SUFFIX=".deb"
    PKG_INSTALL="dpkg -i"
    ARCH="$(dpkg --print-architecture)"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_SUFFIX=".rpm"
    PKG_INSTALL="dnf install -y"
    ARCH="$(uname -m)"
  elif command -v rpm >/dev/null 2>&1; then
    PKG_SUFFIX=".rpm"
    PKG_INSTALL="rpm -i"
    ARCH="$(uname -m)"
  else
    error "Unsupported system: no dpkg / rpm / dnf found"
  fi

  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
  esac

  OS="linux"
}

# ======================
# 获取最新版本
# ======================
fetch_latest_version() {
  info "Fetching latest release version from GitHub…"

  if [ -n "$GITHUB_TOKEN" ]; then
    RESP="$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$API_LATEST")"
  else
    RESP="$(curl -s "$API_LATEST")"
  fi

  VERSION="$(echo "$RESP" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\?\([^"]*\)".*/\1/p')"

  [ -z "$VERSION" ] && {
    echo "$RESP"
    error "Failed to parse tag_name from GitHub API"
  }

  echo "$VERSION"
}

# ======================
# 主流程
# ======================
main() {
  detect_platform

  if [ -z "$DOWNLOAD_VERSION" ]; then
    DOWNLOAD_VERSION="$(fetch_latest_version)"
  fi

  info "Version   : $DOWNLOAD_VERSION"
  info "Platform  : $OS"
  info "Arch      : $ARCH"

  PKG_NAME="${BIN_NAME}-${OS}-${DOWNLOAD_VERSION}-${ARCH}${PKG_SUFFIX}"
  PKG_URL="${DOWNLOAD_BASE}/v${DOWNLOAD_VERSION}/${PKG_NAME}"

  info "Downloading:"
  info "  $PKG_URL"

  curl --fail -L -o "$PKG_NAME" "$PKG_URL" || error "Download failed"

  if command -v sudo >/dev/null 2>&1; then
    PKG_INSTALL="sudo $PKG_INSTALL"
  fi

  info "Installing package…"
  sh -c "$PKG_INSTALL \"$PKG_NAME\""

  info "Cleaning up…"
  rm -f "$PKG_NAME"

  info "✅ mihomo installed successfully"
}

main
