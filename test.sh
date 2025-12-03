#!/bin/sh
#
# 自动登录服务测试脚本
# 用于安装前测试网络接口和登录功能
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}======================================${NC}"
}

print_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# 测试 1: 系统环境检测
test_system() {
    print_header "测试 1: 系统环境检测"

    if [ -f "/etc/openwrt_release" ]; then
        . /etc/openwrt_release
        print_info "系统类型: $DISTRIB_ID"
        print_info "系统版本: $DISTRIB_RELEASE"
        print_info "系统描述: $DISTRIB_DESCRIPTION"
    else
        print_warn "未检测到 OpenWrt 系统"
        print_info "当前系统: $(uname -s)"
        print_info "内核版本: $(uname -r)"
    fi
}

# 测试 2: 依赖工具检测
test_dependencies() {
    print_header "测试 2: 依赖工具检测"

    local all_ok=1

    # 检查 wget
    if command -v wget >/dev/null 2>&1; then
        print_info "wget: $(wget --version | head -n1)"
    else
        print_error "wget: 未安装"
        all_ok=0
    fi

    # 检查 curl
    if command -v curl >/dev/null 2>&1; then
        print_info "curl: $(curl --version | head -n1)"
    else
        print_warn "curl: 未安装（可选）"
    fi

    # 检查 ifconfig
    if command -v ifconfig >/dev/null 2>&1; then
        print_info "ifconfig: 可用"
    else
        print_warn "ifconfig: 未安装，将使用 ip 命令"
    fi

    # 检查 ip
    if command -v ip >/dev/null 2>&1; then
        print_info "ip: $(ip -V 2>&1)"
    else
        print_error "ip: 未安装"
        all_ok=0
    fi

    # 检查 ping
    if command -v ping >/dev/null 2>&1; then
        print_info "ping: 可用"
    else
        print_error "ping: 未安装"
        all_ok=0
    fi

    if [ $all_ok -eq 0 ]; then
        echo ""
        print_warn "部分依赖缺失，运行安装脚本时会自动安装"
    fi
}

# 测试 3: 网络接口检测
test_interfaces() {
    print_header "测试 3: 网络接口检测"

    echo "可用的网络接口："
    echo ""

    # 使用 ip 命令
    if command -v ip >/dev/null 2>&1; then
        ip -br addr show | while read line; do
            iface=$(echo "$line" | awk '{print $1}')
            state=$(echo "$line" | awk '{print $2}')
            addr=$(echo "$line" | awk '{print $3}' | cut -d/ -f1)

            if [ "$state" = "UP" ]; then
                print_info "接口: $iface | 状态: $state | IP: ${addr:-无}"
            else
                echo -e "  接口: $iface | 状态: $state"
            fi
        done
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig | grep -E '^[a-z]' | awk '{print $1}' | sed 's/:$//' | while read iface; do
            addr=$(ifconfig "$iface" | grep "inet addr:" | awk '{print $2}' | cut -d: -f2)
            print_info "接口: $iface | IP: ${addr:-无}"
        done
    fi

    echo ""
    # 检测 WAN 接口
    print_info "尝试自动检测 WAN 接口..."

    local wan_if=""
    # 方法1: UCI
    wan_if=$(uci get network.wan.ifname 2>/dev/null || uci get network.wan.device 2>/dev/null || echo "")
    if [ -n "$wan_if" ]; then
        print_info "UCI 配置: $wan_if"
    fi

    # 方法2: 默认路由
    wan_if=$(ip route | grep default | head -n1 | awk '{print $5}')
    if [ -n "$wan_if" ]; then
        print_info "默认路由接口: $wan_if"
        # 获取该接口的 IP
        wan_ip=$(ip addr show dev "$wan_if" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        if [ -n "$wan_ip" ]; then
            print_info "WAN IP: $wan_ip"
        fi
    fi
}

# 测试 4: 网络连通性测试
test_connectivity() {
    print_header "测试 4: 网络连通性测试"

    local test_hosts="119.29.29.29 223.5.5.5 8.8.8.8"
    local success=0

    for host in $test_hosts; do
        echo -n "  测试 $host ... "
        if ping -c 1 -W 3 "$host" > /dev/null 2>&1; then
            echo -e "${GREEN}成功${NC}"
            success=1
        else
            echo -e "${RED}失败${NC}"
        fi
    done

    if [ $success -eq 1 ]; then
        print_info "网络连接正常"
    else
        print_error "所有测试主机均无法连接"
        print_warn "可能需要先登录认证"
    fi
}

# 测试 5: 登录接口测试
test_login() {
    print_header "测试 5: 登录接口测试（可选）"

    read -p "是否测试登录接口? (y/n): " test_login
    if [ "$test_login" != "y" ] && [ "$test_login" != "Y" ]; then
        print_warn "跳过登录测试"
        return
    fi

    # 获取 WAN 接口
    local wan_if=$(ip route | grep default | head -n1 | awk '{print $5}')
    if [ -z "$wan_if" ]; then
        print_error "无法检测 WAN 接口"
        read -p "请手动输入 WAN 接口名称: " wan_if
    fi

    # 获取 IP
    local current_ip=$(ip addr show dev "$wan_if" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -z "$current_ip" ]; then
        print_error "无法获取 IP 地址"
        return
    fi

    print_info "WAN 接口: $wan_if"
    print_info "本地 IP: $current_ip"

    # 输入登录信息
    read -p "请输入登录账号: " user_account
    read -s -p "请输入登录密码: " user_password
    echo ""
    read -p "运营商选择 (1=联通, 2=移动): " isp_choice
    isp_choice=${isp_choice:-1}

    # 构建 URL
    local url="http://10.10.11.11:801/eportal/portal/login?callback=dr1003&login_method=1&user_account=%2C0%2C${user_account}&user_password=${user_password}&wlan_user_ip=${current_ip}&wlan_user_ipv6=&wlan_user_mac=000000000000&wlan_ac_ip=&wlan_ac_name=&page_index=pMnaGv1756888844&authex_enable=${isp_choice}&jsVersion=4.2.1&terminal_type=1&lang=zh-cn&lang=zh"

    echo ""
    print_info "正在测试登录..."
    echo ""

    # 执行请求
    if command -v wget >/dev/null 2>&1; then
        response=$(wget -qO- --timeout=10 "$url" 2>&1)
    elif command -v curl >/dev/null 2>&1; then
        response=$(curl -s --max-time 10 "$url" 2>&1)
    else
        print_error "wget 和 curl 都不可用"
        return
    fi

    echo "登录响应:"
    echo "$response"
    echo ""

    # 简单分析响应
    if echo "$response" | grep -q "success"; then
        print_info "登录可能成功（响应包含 success）"
    elif echo "$response" | grep -q "error"; then
        print_warn "登录可能失败（响应包含 error）"
    else
        print_warn "无法确定登录结果，请检查上述响应内容"
    fi

    # 再次测试网络
    echo ""
    print_info "等待 5 秒后测试网络..."
    sleep 5

    if ping -c 1 -W 3 119.29.29.29 > /dev/null 2>&1; then
        print_info "网络连接成功！"
    else
        print_warn "网络仍然无法连接"
    fi
}

# 测试 6: 存储空间检测
test_storage() {
    print_header "测试 6: 存储空间检测"

    df -h | grep -E '^Filesystem|/overlay|/$' | while read line; do
        if echo "$line" | grep -q "Filesystem"; then
            echo "$line"
        else
            filesystem=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $2}')
            used=$(echo "$line" | awk '{print $3}')
            avail=$(echo "$line" | awk '{print $4}')
            use_pct=$(echo "$line" | awk '{print $5}')
            mount=$(echo "$line" | awk '{print $6}')

            if [ "${use_pct%\%}" -gt 80 ]; then
                print_warn "$mount: $used/$size 已使用 ($use_pct)"
            else
                print_info "$mount: $used/$size 已使用 ($use_pct)"
            fi
        fi
    done
}

# 生成配置建议
generate_suggestions() {
    print_header "配置建议"

    # 检测 WAN 接口
    local wan_if=$(ip route | grep default | head -n1 | awk '{print $5}')
    if [ -n "$wan_if" ]; then
        echo "WAN 接口建议:"
        echo "  WAN_INTERFACE=\"$wan_if\""
        echo ""
    fi

    # 检测存储空间
    local avail_mb=$(df -m /overlay 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$avail_mb" ]; then
        avail_mb=$(df -m / | tail -1 | awk '{print $4}')
    fi

    echo "日志配置建议:"
    if [ "$avail_mb" -gt 100 ]; then
        echo "  存储空间充足（${avail_mb}MB 可用）"
        echo "  LOG_TYPE=\"1\"  # 文件日志"
        echo "  LOG_SIZE_MB=\"10\"  # 10MB 限制"
    elif [ "$avail_mb" -gt 50 ]; then
        echo "  存储空间一般（${avail_mb}MB 可用）"
        echo "  LOG_TYPE=\"1\"  # 文件日志"
        echo "  LOG_SIZE_MB=\"5\"  # 5MB 限制"
    else
        echo "  存储空间紧张（${avail_mb}MB 可用）"
        echo "  LOG_TYPE=\"2\"  # 建议使用 syslog"
    fi

    echo ""
    echo "检测频率建议:"
    echo "  稳定网络: CHECK_INTERVAL=\"60000\"  # 60秒"
    echo "  一般网络: CHECK_INTERVAL=\"30000\"  # 30秒（推荐）"
    echo "  不稳定网络: CHECK_INTERVAL=\"10000\"  # 10秒"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║   OpenWrt 自动登录服务 - 测试工具   ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"

    test_system
    test_dependencies
    test_interfaces
    test_connectivity
    test_login
    test_storage
    generate_suggestions

    echo ""
    print_header "测试完成"
    echo ""
    echo "如果所有测试通过，可以运行安装脚本："
    echo "  chmod +x install.sh && ./install.sh"
    echo ""
}

# 运行主函数
main
