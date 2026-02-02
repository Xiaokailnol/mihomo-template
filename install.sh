#!/bin/sh
set -e

# ======================
# 颜色定义
# ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ======================
# 样式函数
# ======================
print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}${WHITE}Mihomo Installer${NC} ${BLUE}✦${NC} ${YELLOW}v1.0.0${NC}                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_separator() {
    echo -e "${PURPLE}──────────────────────────────────────────────────────────${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}●${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1" >&2
}

print_step() {
    echo -e "${GREEN}[${WHITE}STEP${GREEN}]${NC} ${BOLD}$1${NC}" >&2
}

print_status() {
    echo -e "${BLUE}[${WHITE}STATUS${BLUE}]${NC} $1" >&2
}

# ======================
# 基础配置
# ======================
REPO_OWNER="Xiaokailnol"
REPO_NAME="mihomo-template"
BIN_NAME="mihomo"

API_LATEST="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download"

# ======================
# 参数解析
# ======================
DOWNLOAD_VERSION=""
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            shift
            [ -z "$1" ] && { print_error "Missing argument for --version"; exit 1; }
            DOWNLOAD_VERSION="$1"
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_header
            echo -e "${WHITE}Usage:${NC} $0 [options]"
            echo
            echo -e "${WHITE}Options:${NC}"
            echo -e "  ${CYAN}--version <version>${NC}   Install specific version"
            echo -e "  ${CYAN}--verbose, -v${NC}         Enable verbose output"
            echo -e "  ${CYAN}--help, -h${NC}            Show this help message"
            echo
            echo -e "${WHITE}Example:${NC}"
            echo -e "  $0 --version 1.0.4"
            echo -e "  $0 --verbose"
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            echo -e "  Use ${CYAN}$0 --help${NC} for usage information"
            exit 1
            ;;
    esac
done

# ======================
# 系统检测
# ======================
detect_platform() {
    print_step "Detecting system platform..."
    
    if command -v dpkg >/dev/null 2>&1; then
        PKG_SUFFIX=".deb"
        PKG_INSTALL="dpkg -i"
        ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
        print_info "Detected Debian-based system"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_SUFFIX=".rpm"
        PKG_INSTALL="dnf install -y"
        ARCH="$(uname -m)"
        print_info "Detected Fedora-based system (dnf)"
    elif command -v yum >/dev/null 2>&1; then
        PKG_SUFFIX=".rpm"
        PKG_INSTALL="yum install -y"
        ARCH="$(uname -m)"
        print_info "Detected RHEL-based system (yum)"
    elif command -v rpm >/dev/null 2>&1; then
        PKG_SUFFIX=".rpm"
        PKG_INSTALL="rpm -i"
        ARCH="$(uname -m)"
        print_info "Detected RPM-based system"
    else
        print_error "Unsupported system: no dpkg / rpm / dnf / yum found"
        exit 1
    fi

    # 规范化架构名称
    case "$ARCH" in
        x86_64|amd64) 
            ARCH="amd64"
            print_info "Architecture: x86_64 (amd64)"
            ;;
        aarch64|arm64) 
            ARCH="arm64"
            print_info "Architecture: ARM64"
            ;;
        armv7l|armhf)
            ARCH="arm"
            print_info "Architecture: ARMv7"
            ;;
        i386|i686)
            ARCH="386"
            print_info "Architecture: x86 (32-bit)"
            ;;
        *)
            print_warning "Unknown architecture: $ARCH, attempting to use as-is"
            ;;
    esac

    OS="linux"
    print_success "Platform detection completed"
}

# ======================
# 获取版本号 (修复版本 - 主要修复在这里)
# ======================
fetch_latest_version() {
    # 将进度信息输出到 stderr，避免污染 stdout
    print_step "Checking for latest release..." >&2
    
    local response
    if [ -n "$GITHUB_TOKEN" ]; then
        if [ $VERBOSE -eq 1 ]; then
            print_status "Using GitHub token for authentication" >&2
        fi
        response="$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$API_LATEST" 2>/dev/null || curl -s "$API_LATEST")"
    else
        response="$(curl -s "$API_LATEST")"
    fi
    
    if [ -z "$response" ] || echo "$response" | grep -q "API rate limit"; then
        print_warning "GitHub API may be rate limited, using default version" >&2
        # 如果没有从API获取到版本，可以设置一个默认版本
        echo "latest"
        return 0
    fi
    
    # 使用更可靠的方式提取版本号
    local version
    version="$(echo "$response" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
    
    # 移除可能的 'v' 前缀
    version="${version#v}"
    
    if [ -z "$version" ]; then
        if [ $VERBOSE -eq 1 ]; then
            print_status "Raw API response:" >&2
            echo "$response" | head -20 >&2
        fi
        print_error "Failed to parse version from GitHub API" >&2
        exit 1
    fi
    
    print_info "Latest version: ${YELLOW}v${version}${NC}" >&2
    
    # 清理版本号，移除所有非版本字符
    version="$(echo "$version" | tr -cd '0-9.\n')"
    
    # 输出纯版本号到 stdout
    echo "$version"
}

# ======================
# 下载文件
# ======================
download_package() {
    local url="$1"
    local output="$2"
    
    print_step "Downloading package..."
    print_status "URL: ${CYAN}$url${NC}"
    
    # 使用 curl 下载，添加进度显示
    if [ $VERBOSE -eq 1 ]; then
        curl -fL -o "$output" "$url" || {
            print_error "Download failed"
            rm -f "$output" 2>/dev/null
            return 1
        }
    else
        curl -fL -# -o "$output" "$url" || {
            print_error "Download failed"
            rm -f "$output" 2>/dev/null
            return 1
        }
    fi
    
    # 检查文件大小
    local size
    size="$(du -h "$output" | cut -f1)"
    print_success "Download completed (${size}B)"
}

# ======================
# 主流程
# ======================
main() {
    print_header
    
    # 检测系统
    detect_platform
    
    # 获取版本
    if [ -z "$DOWNLOAD_VERSION" ]; then
        DOWNLOAD_VERSION="$(fetch_latest_version)"
    else
        print_info "Using specified version: ${YELLOW}v${DOWNLOAD_VERSION}${NC}"
    fi
    
    # 清理版本号中的换行符和多余空格
    DOWNLOAD_VERSION="$(echo "$DOWNLOAD_VERSION" | tr -d '[:space:]')"
    
    print_separator
    print_status "Installation Summary:"
    print_info "Version:    ${WHITE}v${DOWNLOAD_VERSION}${NC}"
    print_info "System:     ${WHITE}${OS}${NC}"
    print_info "Arch:       ${WHITE}${ARCH}${NC}"
    
    # 构造包名和URL
    PKG_NAME="${BIN_NAME}-${OS}-${DOWNLOAD_VERSION}-${ARCH}${PKG_SUFFIX}"
    PKG_URL="${DOWNLOAD_BASE}/v${DOWNLOAD_VERSION}/${PKG_NAME}"
    
    print_info "Package:    ${WHITE}${PKG_NAME}${NC}"
    print_separator
    
    # 下载
    if ! download_package "$PKG_URL" "$PKG_NAME"; then
        print_error "Please check the URL or try again later"
        exit 1
    fi
    
    # 安装
    print_step "Installing package..."
    if command -v sudo >/dev/null 2>&1; then
        print_status "Using sudo for installation"
        if ! sudo $PKG_INSTALL "$PKG_NAME"; then
            print_error "Installation failed. Check permissions or package format."
            rm -f "$PKG_NAME"
            exit 1
        fi
    else
        print_status "Running as root user"
        if ! $PKG_INSTALL "$PKG_NAME"; then
            print_error "Installation failed. Check permissions or package format."
            rm -f "$PKG_NAME"
            exit 1
        fi
    fi
    
    # 清理
    print_step "Cleaning up..."
    rm -f "$PKG_NAME"
    
    print_separator
    print_success "${GREEN}${BOLD}Installation completed successfully!${NC}"
    echo
    print_info "Next steps:"
    echo -e "  1. Configure mihomo: ${CYAN}sudo nano /etc/mihomo/config.yaml${NC}"
    echo -e "  2. Start service:    ${CYAN}sudo systemctl start mihomo${NC}"
    echo -e "  3. Enable on boot:   ${CYAN}sudo systemctl enable mihomo${NC}"
    echo
    print_info "For more information, visit:"
    echo -e "  ${CYAN}https://github.com/${REPO_OWNER}/${REPO_NAME}${NC}"
    echo
}

# 错误处理
trap 'print_error "Script interrupted by user"; exit 1' INT TERM

# 运行主函数
main "$@"
