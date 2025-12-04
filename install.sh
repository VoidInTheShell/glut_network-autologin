#!/bin/sh
#
# OpenWrt 自动登录服务安装脚本
# 自动检测环境、安装依赖、配置服务
#

set -e

INSTALL_DIR="/usr/local/autologin"
CONFIG_FILE="/etc/config/autologin"
SERVICE_FILE="/etc/init.d/autologin"
SCRIPT_FILE="$INSTALL_DIR/login.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测是否为 OpenWrt 系统
check_system() {
    print_info "检测系统环境..."
    if [ ! -f "/etc/openwrt_release" ]; then
        print_warn "警告: 未检测到 OpenWrt 系统标识文件"
        read -p "是否继续安装? (y/n): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            exit 1
        fi
    else
        . /etc/openwrt_release
        print_info "系统: $DISTRIB_ID $DISTRIB_RELEASE"
    fi
}

# 检测并安装依赖
check_dependencies() {
    print_info "检测依赖包..."
    local missing_deps=""
    local deps="wget curl"
    local critical_cmds="ip ping sleep awk grep cut"

    # 检查可通过opkg安装的依赖
    for dep in $deps; do
        if ! command -v $dep >/dev/null 2>&1; then
            missing_deps="$missing_deps $dep"
        fi
    done

    # 检查关键系统命令（通常预装，但需验证）
    local missing_critical=""
    for cmd in $critical_cmds; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_critical="$missing_critical $cmd"
        fi
    done

    if [ -n "$missing_critical" ]; then
        print_error "缺少关键系统命令:$missing_critical"
        print_error "这些命令应该预装在OpenWrt中，请检查系统完整性"
        return 1
    fi

    if [ -n "$missing_deps" ]; then
        print_warn "缺失依赖包:$missing_deps"
        print_info "正在更新软件源..."
        if ! opkg update; then
            print_error "软件源更新失败，请检查网络连接"
            return 1
        fi

        for dep in $missing_deps; do
            print_info "正在安装 $dep..."
            if ! opkg install $dep; then
                print_error "安装 $dep 失败"
                return 1
            fi
        done
    else
        print_info "所有依赖已满足"
    fi

    return 0
}

# 获取 WAN 接口名称
get_wan_interface() {
    # 尝试多种方法获取 WAN 接口
    local wan_if=""

    # 方法1: 通过 uci 获取
    wan_if=$(uci get network.wan.ifname 2>/dev/null || uci get network.wan.device 2>/dev/null || echo "")

    # 方法2: 通过 ip route 获取默认网关接口
    if [ -z "$wan_if" ]; then
        wan_if=$(ip route | grep default | head -n1 | awk '{print $5}')
    fi

    # 方法3: 常见接口名猜测
    if [ -z "$wan_if" ]; then
        for if_name in eth1 eth0.2 wan; do
            if ifconfig $if_name >/dev/null 2>&1; then
                wan_if=$if_name
                break
            fi
        done
    fi

    echo "$wan_if"
}

# 交互式配置
interactive_config() {
    print_info "开始配置登录服务..."
    echo ""

    # 自动检测 WAN 接口
    WAN_IF=$(get_wan_interface)
    if [ -n "$WAN_IF" ]; then
        print_info "自动检测到 WAN 接口: $WAN_IF"
        read -p "是否使用此接口? (Y/n): " use_auto
        if [ "$use_auto" = "n" ] || [ "$use_auto" = "N" ]; then
            read -p "请输入 WAN 接口名称: " WAN_IF
        fi
    else
        read -p "请输入 WAN 接口名称 (如 eth1): " WAN_IF
    fi

    # 账号密码
    read -p "请输入登录账号: " USER_ACCOUNT
    read -s -p "请输入登录密码: " USER_PASSWORD
    echo ""

    # 运营商选择
    echo "请选择运营商:"
    echo "  1) 联通"
    echo "  2) 移动"
    read -p "请输入选项 (1/2) [默认: 1]: " ISP_CHOICE
    ISP_CHOICE=${ISP_CHOICE:-1}

    # 检测策略配置
    echo ""
    print_info "检测策略配置"
    echo "系统使用双层检测策略："
    echo "  • 主检测: 公网DNS Ping (快速响应，不受认证服务器限制)"
    echo "  • 辅助检测: 本地认证服务器HTTP状态 (fallback验证)"
    echo ""
    echo "注意: 认证服务器有防护机制，高频HTTP请求会被强制登出"
    echo ""

    # 在线状态检测频率
    print_info "在线状态检测频率"
    read -p "公网DNS检测频率 (秒) [默认: 10]: " DNS_CHECK_INTERVAL
    DNS_CHECK_INTERVAL=${DNS_CHECK_INTERVAL:-10}

    read -p "本地HTTP检测频率 (秒，最小60秒以避免被登出) [默认: 60]: " AUTH_HTTP_CHECK_INTERVAL
    AUTH_HTTP_CHECK_INTERVAL=${AUTH_HTTP_CHECK_INTERVAL:-60}
    # 确保不小于60秒
    if [ "$AUTH_HTTP_CHECK_INTERVAL" -lt 60 ]; then
        print_warn "本地HTTP检测频率不能小于60秒，已自动调整为60秒"
        AUTH_HTTP_CHECK_INTERVAL=60
    fi

    # 离线状态重连配置
    echo ""
    print_info "离线状态重连配置"
    read -p "离线重连等待时间 (秒) [默认: 3]: " RECONNECT_INTERVAL
    RECONNECT_INTERVAL=${RECONNECT_INTERVAL:-3}

    # DNS失败阈值配置
    echo ""
    print_info "DNS离线判定策略"
    echo "当多个DNS服务器检测失败时，判定为离线："
    echo "  1) 任何1个DNS失败就离线 (最敏感，快速反应，可能误判)"
    echo "  2) 至少2个DNS失败才离线 (推荐，平衡误判和延迟)"
    echo "  3) 所有DNS都失败才离线 (最保守，可能延迟发现断线)"
    read -p "请选择策略 (1/2/3) [默认: 2]: " DNS_FAILURE_THRESHOLD_OPTION
    DNS_FAILURE_THRESHOLD_OPTION=${DNS_FAILURE_THRESHOLD_OPTION:-2}

    case "$DNS_FAILURE_THRESHOLD_OPTION" in
        1) DNS_FAILURE_THRESHOLD=1 ;;
        3) DNS_FAILURE_THRESHOLD=999 ;;  # 使用999表示"所有"
        *) DNS_FAILURE_THRESHOLD=2 ;;
    esac

    # 在线判定策略
    echo ""
    print_info "在线判定策略"
    echo "从离线恢复到在线状态的条件："
    echo "  1) 仅依赖DNS检测 (达到DNS阈值即判定在线)"
    echo "  2) DNS + HTTP双重验证 (至少1个DNS可达 + 本地HTTP在线)"
    read -p "请选择策略 (1/2) [默认: 2]: " ONLINE_VERIFY_STRATEGY
    ONLINE_VERIFY_STRATEGY=${ONLINE_VERIFY_STRATEGY:-2}

    # 公网DNS服务器配置
    echo ""
    print_info "公网DNS服务器配置"
    echo "用于辅助验证网络连通性（负载均衡轮询）"
    read -p "公网DNS服务器 [默认: 119.29.29.29 223.5.5.5 1.1.1.1]: " DNS_TEST_SERVERS
    DNS_TEST_SERVERS=${DNS_TEST_SERVERS:-"119.29.29.29 223.5.5.5 1.1.1.1"}

    # 固定启用的检测方法（移除公网HTTP重定向）
    ENABLE_AUTH_HTTP="Y"
    ENABLE_PUBLIC_HTTP="N"
    ENABLE_PUBLIC_PING="Y"
    HTTP_TEST_URLS=""

    # 日志配置
    echo ""
    print_info "日志配置"
    echo "请选择日志输出方式:"
    echo "  1) 输出到文件 (可限制大小)"
    echo "  2) 输出到 syslog (系统日志)"
    echo "  3) 输出到 /dev/null (不记录)"
    read -p "请输入选项 (1/2/3) [默认: 1]: " LOG_TYPE
    LOG_TYPE=${LOG_TYPE:-1}

    if [ "$LOG_TYPE" = "1" ]; then
        read -p "请输入日志大小限制 (MB) [默认: 10]: " LOG_SIZE_MB
        LOG_SIZE_MB=${LOG_SIZE_MB:-10}
        LOG_DIR="$INSTALL_DIR/logs"
        LOG_FILE="$LOG_DIR/autologin.log"
    elif [ "$LOG_TYPE" = "2" ]; then
        LOG_FILE="logger -t autologin"
        LOG_SIZE_MB=0
    else
        LOG_FILE="/dev/null"
        LOG_SIZE_MB=0
    fi

    echo ""
    print_info "配置摘要:"
    echo "  WAN 接口: $WAN_IF"
    echo "  登录账号: $USER_ACCOUNT"
    echo "  运营商: $([ "$ISP_CHOICE" = "1" ] && echo "联通" || echo "移动")"
    echo ""
    echo "  检测策略:"
    echo "    主检测: 公网DNS Ping"
    echo "    辅助检测: 本地认证服务器HTTP"
    echo ""
    echo "  在线状态检测频率:"
    echo "    公网DNS检测: 每 ${DNS_CHECK_INTERVAL} 秒"
    echo "    本地HTTP检测: 每 ${AUTH_HTTP_CHECK_INTERVAL} 秒"
    echo ""
    echo "  离线状态配置:"
    echo "    重连等待时间: ${RECONNECT_INTERVAL} 秒"
    echo ""
    echo "  判定策略:"
    case "$DNS_FAILURE_THRESHOLD" in
        1) echo "    DNS离线判定: 任何1个DNS失败即离线" ;;
        999) echo "    DNS离线判定: 所有DNS都失败才离线" ;;
        *) echo "    DNS离线判定: 至少${DNS_FAILURE_THRESHOLD}个DNS失败才离线" ;;
    esac
    case "$ONLINE_VERIFY_STRATEGY" in
        1) echo "    在线判定: 仅依赖DNS检测" ;;
        2) echo "    在线判定: DNS + HTTP双重验证" ;;
    esac
    echo ""
    echo "  公网DNS服务器: $DNS_TEST_SERVERS"
    echo ""
    if [ "$LOG_TYPE" = "1" ]; then
        echo "  日志文件: $LOG_FILE"
        echo "  日志大小: $LOG_SIZE_MB MB"
    elif [ "$LOG_TYPE" = "2" ]; then
        echo "  日志输出: syslog"
    else
        echo "  日志输出: 禁用"
    fi
    echo ""

    read -p "确认以上配置并继续安装? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_error "安装已取消"
        exit 1
    fi
}

# 创建安装目录
create_directories() {
    print_info "创建安装目录..."
    mkdir -p "$INSTALL_DIR"
    if [ "$LOG_TYPE" = "1" ]; then
        mkdir -p "$LOG_DIR"
    fi
}

# 生成登录脚本
generate_login_script() {
    print_info "生成登录脚本..."

    cat > "$SCRIPT_FILE" << 'EOFSCRIPT'
#!/bin/sh
#
# 自动登录脚本 - 双层检测状态机版本
# 由安装程序自动生成
#

# 配置文件
CONFIG_FILE="/etc/config/autologin"

# 全局状态变量
CURRENT_STATE="UNKNOWN"  # ONLINE, SUSPECT, OFFLINE, RECOVERING, UNKNOWN
START_TIME=0
LAST_DNS_CHECK=0
LAST_HTTP_CHECK=0
LAST_STATUS_LOG=0
DNS_SERVER_INDEX=0
DNS_CONSECUTIVE_FAILURES=0  # DNS连续失败计数器
RECOVERING_SUCCESS_COUNT=0  # 恢复状态成功计数
OFFLINE_DNS_CHECK_INTERVAL=5  # 离线状态下DNS检测间隔（秒）
OFFLINE_HTTP_CHECK_INTERVAL=60  # 离线状态下HTTP检测间隔（秒）

# ============ 命令兼容性检测 ============
# 检查命令是否可用
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证关键命令
check_required_commands() {
    local missing=""
    for cmd in ip ifconfig ping wget sleep date; do
        if ! command_exists "$cmd"; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        log_message "错误: 缺少必需命令:$missing"
        return 1
    fi
    return 0
}

# 安全的sleep函数（确保参数为正整数）
safe_sleep() {
    local seconds="$1"
    # 验证是否为数字
    case "$seconds" in
        ''|*[!0-9]*)
            log_message "警告: sleep参数无效 ($seconds), 使用默认值1秒"
            seconds=1
            ;;
    esac
    # 确保至少sleep 1秒
    if [ "$seconds" -lt 1 ]; then
        seconds=1
    fi
    sleep "$seconds"
}

# 获取当前时间戳（秒）
get_timestamp() {
    date +%s
}

# 读取配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        echo "错误: 配置文件不存在"
        exit 1
    fi
}

# 获取 WAN 口 IP 地址
get_wan_ip() {
    local ip=""

    # 方法1: 使用 ip addr
    ip=$(ip addr show dev "$WAN_INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)

    # 方法2: 使用 ifconfig (兼容旧版本)
    if [ -z "$ip" ]; then
        ip=$(ifconfig "$WAN_INTERFACE" 2>/dev/null | grep "inet addr:" | awk '{print $2}' | cut -d: -f2)
    fi

    # 方法3: 使用 uci + ifconfig
    if [ -z "$ip" ]; then
        ip=$(ifconfig "$WAN_INTERFACE" 2>/dev/null | grep -oE "inet addr:[0-9.]+" | cut -d: -f2)
    fi

    echo "$ip"
}

# 获取 MAC 地址
get_wan_mac() {
    local mac=""

    # 方法1: 使用 ip link
    mac=$(ip link show dev "$WAN_INTERFACE" 2>/dev/null | grep "link/ether" | awk '{print $2}' | tr ':' '-')

    # 方法2: 使用 ifconfig
    if [ -z "$mac" ]; then
        mac=$(ifconfig "$WAN_INTERFACE" 2>/dev/null | grep "HWaddr" | awk '{print $5}' | tr '[:upper:]' '[:lower:]' | tr ':' '-')
    fi

    echo "$mac"
}

# 日志输出函数
log_message() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local message="$1"

    if [ "$LOG_TYPE" = "1" ]; then
        # 检查日志大小
        if [ -f "$LOG_FILE" ]; then
            local size=$(du -m "$LOG_FILE" | cut -f1)
            if [ "$size" -ge "$LOG_SIZE_MB" ]; then
                # 日志轮转
                mv "$LOG_FILE" "$LOG_FILE.old"
                echo "[$timestamp] 日志已轮转" > "$LOG_FILE"
            fi
        fi
        echo "[$timestamp] $message" >> "$LOG_FILE"
    elif [ "$LOG_TYPE" = "2" ]; then
        logger -t autologin "$message"
    fi
}

# 日志输出函数（带强制标记，用于重要事件）
log_message_force() {
    log_message "$1"
}

# 状态摘要日志（每10分钟记录一次）
log_status_summary() {
    local current_time=$(get_timestamp)
    local time_since_last_log=$((current_time - LAST_STATUS_LOG))

    # 在线状态下每10分钟记录一次，离线状态不记录摘要
    if [ "$CURRENT_STATE" = "ONLINE" ] && [ $time_since_last_log -ge 600 ]; then
        LAST_STATUS_LOG=$current_time
        log_message "==== 状态摘要 ===="
        log_message "当前状态: 在线 (ONLINE)"
        log_message "运行时长: $((current_time - START_TIME)) 秒"
        log_message "检测模式: 轮询（低频节能）"
        log_message "  - DNS轮询索引: $DNS_SERVER_INDEX"
        log_message "  - 连续失败计数: $DNS_CONSECUTIVE_FAILURES"
        log_message "=================="
    fi
}

# 执行登录请求
do_login() {
    local current_ip=$(get_wan_ip)
    local mac_address=$(get_wan_mac)

    if [ -z "$current_ip" ]; then
        log_message "错误: 无法获取 WAN 口 IP 地址 (接口: $WAN_INTERFACE)"
        return 1
    fi

    log_message "尝试登录 - IP: $current_ip, MAC: $mac_address"

    # 构建登录 URL
    local url="http://${AUTH_SERVER}:${AUTH_PORT_801}/eportal/portal/login?callback=dr1003&login_method=1&user_account=%2C0%2C${USER_ACCOUNT}&user_password=${USER_PASSWORD}&wlan_user_ip=${current_ip}&wlan_user_ipv6=&wlan_user_mac=000000000000&wlan_ac_ip=&wlan_ac_name=&page_index=pMnaGv1756888844&authex_enable=${ISP_CHOICE}&jsVersion=4.2.1&terminal_type=1&lang=zh-cn&lang=zh"

    # 执行登录请求
    local response=$(wget -qO- --timeout=5 "$url" 2>&1)
    log_message "登录响应: $response"

    return 0
}

# ============================================
# 检测方法
# ============================================

# 方法1: 认证服务器HTTP状态检测（静默，不记录日志）
check_auth_http() {
    if [ "$ENABLE_AUTH_HTTP" != "Y" ] && [ "$ENABLE_AUTH_HTTP" != "y" ]; then
        return 2
    fi

    local response=$(wget --timeout=2 --tries=1 --server-response -qO- "http://${AUTH_SERVER}/" 2>&1)
    local wget_exit=$?

    if [ $wget_exit -eq 0 ]; then
        if echo "$response" | grep -q "Dr.COMWebLoginID_3.htm"; then
            return 0  # 在线
        elif echo "$response" | grep -q "Dr.COMWebLoginID_2.htm"; then
            return 1  # 离线
        fi
    fi
    return 2  # 不确定
}

# 方法1: 认证服务器HTTP状态检测（带日志输出）
check_auth_http_with_log() {
    if [ "$ENABLE_AUTH_HTTP" != "Y" ] && [ "$ENABLE_AUTH_HTTP" != "y" ]; then
        return 2
    fi

    local temp_file="/tmp/auth_http_check.$$"
    local response=$(wget --timeout=2 --tries=1 --server-response -qO- "http://${AUTH_SERVER}/" 2>&1 | tee "$temp_file")
    local wget_exit=$?

    # 提取HTTP状态码
    local http_code=$(grep "HTTP/" "$temp_file" | tail -1 | awk '{print $2}')
    rm -f "$temp_file"

    if [ -z "$http_code" ]; then
        http_code="无响应"
    fi

    if [ $wget_exit -eq 0 ]; then
        if echo "$response" | grep -q "Dr.COMWebLoginID_3.htm"; then
            log_message "认证服务器HTTP检测: 在线 (状态码: $http_code)"
            return 0  # 在线
        elif echo "$response" | grep -q "Dr.COMWebLoginID_2.htm"; then
            log_message "认证服务器HTTP检测: 离线/未认证 (状态码: $http_code)"
            return 1  # 离线
        else
            log_message "认证服务器HTTP检测: 无法判断状态 (状态码: $http_code)"
        fi
    else
        log_message "认证服务器HTTP检测: 连接失败 (退出码: $wget_exit)"
    fi
    return 2  # 不确定
}

# 方法2a: 公网DNS Ping检测（并行模式，用于快速验证）
check_public_ping_parallel() {
    if [ "$ENABLE_PUBLIC_PING" != "Y" ] && [ "$ENABLE_PUBLIC_PING" != "y" ]; then
        return 2
    fi

    # 将空格分隔的DNS转换为列表
    local dns_list=""
    for dns in $DNS_TEST_SERVERS; do
        dns_list="$dns_list $dns"
    done

    # 计算DNS数量
    local dns_count=0
    for dns in $dns_list; do
        dns_count=$((dns_count + 1))
    done

    if [ $dns_count -eq 0 ]; then
        return 2
    fi

    # 先ping认证服务器（确保本地网络正常）
    if ! ping -c 1 -W 1 "$AUTH_SERVER" >/dev/null 2>&1; then
        return 1  # 本地网络故障
    fi

    # 并行检测所有DNS服务器（快速判定）
    local success_count=0
    local fail_count=0

    for dns in $dns_list; do
        if ping -c 1 -W 1 "$dns" >/dev/null 2>&1; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    # 判断逻辑：任意1个成功即在线，2个以上失败才离线
    if [ $success_count -ge 1 ]; then
        return 0  # 至少1个在线，判定在线
    else
        return 1  # 全部失败，判定离线
    fi
}

# 方法2a: 公网DNS Ping检测（并行模式，带日志）
check_public_ping_parallel_with_log() {
    if [ "$ENABLE_PUBLIC_PING" != "Y" ] && [ "$ENABLE_PUBLIC_PING" != "y" ]; then
        return 2
    fi

    # 将空格分隔的DNS转换为列表
    local dns_list=""
    for dns in $DNS_TEST_SERVERS; do
        dns_list="$dns_list $dns"
    done

    # 计算DNS数量
    local dns_count=0
    for dns in $dns_list; do
        dns_count=$((dns_count + 1))
    done

    if [ $dns_count -eq 0 ]; then
        return 2
    fi

    # 先ping认证服务器（确保本地网络正常）
    if ! ping -c 1 -W 1 "$AUTH_SERVER" >/dev/null 2>&1; then
        log_message "并行DNS检测: 认证服务器 $AUTH_SERVER 不可达 (本地网络故障)"
        return 1
    fi

    # 并行检测所有DNS服务器
    local success_count=0
    local fail_count=0
    local success_list=""
    local fail_list=""

    for dns in $dns_list; do
        if ping -c 1 -W 1 "$dns" >/dev/null 2>&1; then
            success_count=$((success_count + 1))
            success_list="$success_list $dns"
        else
            fail_count=$((fail_count + 1))
            fail_list="$fail_list $dns"
        fi
    done

    # 记录详细日志
    log_message "并行DNS检测: 成功 $success_count/$dns_count, 失败 $fail_count/$dns_count"
    [ -n "$success_list" ] && log_message "  可达:$success_list"
    [ -n "$fail_list" ] && log_message "  不可达:$fail_list"

    # 判断逻辑
    if [ $success_count -ge 1 ]; then
        log_message "  判定: 在线 (至少1个DNS可达)"
        return 0
    else
        log_message "  判定: 离线 (所有DNS不可达)"
        return 1
    fi
}

# 方法2b: 公网DNS Ping检测（轮询模式，静默）
check_public_ping() {
    if [ "$ENABLE_PUBLIC_PING" != "Y" ] && [ "$ENABLE_PUBLIC_PING" != "y" ]; then
        return 2
    fi

    # 将空格分隔的DNS转换为列表
    local dns_list=""
    for dns in $DNS_TEST_SERVERS; do
        dns_list="$dns_list $dns"
    done

    # 计算DNS数量
    local dns_count=0
    for dns in $dns_list; do
        dns_count=$((dns_count + 1))
    done

    if [ $dns_count -eq 0 ]; then
        return 2
    fi

    # 先ping认证服务器（确保本地网络正常）
    if ! ping -c 1 -W 1 "$AUTH_SERVER" >/dev/null 2>&1; then
        DNS_CONSECUTIVE_FAILURES=$((DNS_CONSECUTIVE_FAILURES + 1))
        if [ $DNS_CONSECUTIVE_FAILURES -ge 2 ]; then
            return 1  # 本地网络故障，连续失败
        fi
        return 0  # 首次失败，不立即判定离线
    fi

    # 轮询检测：选择当前索引的DNS服务器
    local current_index=0
    local target_dns=""
    for dns in $dns_list; do
        if [ $current_index -eq $DNS_SERVER_INDEX ]; then
            target_dns="$dns"
            break
        fi
        current_index=$((current_index + 1))
    done

    # 更新索引，下次检测下一个DNS（循环）
    DNS_SERVER_INDEX=$(((DNS_SERVER_INDEX + 1) % dns_count))

    # 检测当前DNS服务器
    if ping -c 1 -W 2 "$target_dns" >/dev/null 2>&1; then
        # 成功：重置连续失败计数器
        DNS_CONSECUTIVE_FAILURES=0
        return 0  # 在线
    else
        # 失败：增加连续失败计数器
        DNS_CONSECUTIVE_FAILURES=$((DNS_CONSECUTIVE_FAILURES + 1))
        if [ $DNS_CONSECUTIVE_FAILURES -ge 2 ]; then
            return 1  # 连续2次失败，判定离线
        fi
        return 0  # 首次失败，不立即判定离线
    fi
}

# 方法2: 公网DNS Ping检测（轮询模式，带日志输出）
check_public_ping_with_log() {
    if [ "$ENABLE_PUBLIC_PING" != "Y" ] && [ "$ENABLE_PUBLIC_PING" != "y" ]; then
        return 2
    fi

    # 将空格分隔的DNS转换为列表
    local dns_list=""
    for dns in $DNS_TEST_SERVERS; do
        dns_list="$dns_list $dns"
    done

    # 计算DNS数量
    local dns_count=0
    for dns in $dns_list; do
        dns_count=$((dns_count + 1))
    done

    if [ $dns_count -eq 0 ]; then
        return 2
    fi

    # 先ping认证服务器（确保本地网络正常）
    if ! ping -c 1 -W 1 "$AUTH_SERVER" >/dev/null 2>&1; then
        DNS_CONSECUTIVE_FAILURES=$((DNS_CONSECUTIVE_FAILURES + 1))
        log_message "公网DNS Ping检测: 认证服务器 $AUTH_SERVER 不可达 (连续失败: $DNS_CONSECUTIVE_FAILURES)"
        if [ $DNS_CONSECUTIVE_FAILURES -ge 2 ]; then
            log_message "  判定: 离线 (本地网络连续失败 >= 2次)"
            return 1  # 本地网络故障，连续失败
        fi
        log_message "  判定: 暂不判定离线 (首次失败)"
        return 0  # 首次失败，不立即判定离线
    fi

    # 轮询检测：选择当前索引的DNS服务器
    local current_index=0
    local target_dns=""
    for dns in $dns_list; do
        if [ $current_index -eq $DNS_SERVER_INDEX ]; then
            target_dns="$dns"
            break
        fi
        current_index=$((current_index + 1))
    done

    log_message "公网DNS Ping检测: 轮询检测 DNS[$((DNS_SERVER_INDEX))]=$target_dns (连续失败计数: $DNS_CONSECUTIVE_FAILURES)"

    # 更新索引，下次检测下一个DNS（循环）
    DNS_SERVER_INDEX=$(((DNS_SERVER_INDEX + 1) % dns_count))

    # 检测当前DNS服务器
    if ping -c 1 -W 2 "$target_dns" >/dev/null 2>&1; then
        # 成功：重置连续失败计数器
        log_message "  结果: 可达"
        DNS_CONSECUTIVE_FAILURES=0
        log_message "  判定: 在线 (连续失败计数器已重置)"
        return 0  # 在线
    else
        # 失败：增加连续失败计数器
        DNS_CONSECUTIVE_FAILURES=$((DNS_CONSECUTIVE_FAILURES + 1))
        log_message "  结果: 不可达 (连续失败计数: $DNS_CONSECUTIVE_FAILURES)"
        if [ $DNS_CONSECUTIVE_FAILURES -ge 2 ]; then
            log_message "  判定: 离线 (连续失败 >= 2次)"
            return 1  # 连续2次失败，判定离线
        fi
        log_message "  判定: 暂不判定离线 (首次失败)"
        return 0  # 首次失败，不立即判定离线
    fi
}

# ============================================
# 状态机主逻辑 - 4状态自适应检测
# ============================================

# 在线状态处理（ONLINE）- 低频轮询检测
handle_online_state() {
    # 定期记录状态摘要
    log_status_summary

    local current_time=$(get_timestamp)

    # 轮询检测：每DNS_CHECK_INTERVAL秒检测1个DNS
    local time_since_last_dns=$((current_time - LAST_DNS_CHECK))

    if [ $time_since_last_dns -ge $DNS_CHECK_INTERVAL ]; then
        LAST_DNS_CHECK=$current_time
        check_public_ping  # 轮询模式
        local dns_result=$?

        if [ $dns_result -eq 1 ]; then
            # 单次失败，进入疑似离线状态快速验证
            log_message_force "*** 状态变化: 在线 -> 疑似离线 (轮询检测失败，启动快速验证) ***"
            CURRENT_STATE="SUSPECT"
            return
        fi
        # dns_result=0，继续在线状态
    fi

    # 在线状态不检测认证服务器HTTP，避免被强制下线
    safe_sleep 1
}

# 疑似离线状态处理（SUSPECT）- 并行快速验证
handle_suspect_state() {
    log_message_force "疑似离线状态，立即启动并行快速验证..."

    # 立即并行检测所有DNS（1秒超时）
    check_public_ping_parallel_with_log
    local parallel_result=$?

    if [ $parallel_result -eq 0 ]; then
        # 并行检测通过，是误报，回到在线状态
        log_message_force "*** 状态变化: 疑似离线 -> 在线 (快速验证通过，误报) ***"
        DNS_CONSECUTIVE_FAILURES=0  # 重置计数器
        CURRENT_STATE="ONLINE"
        LAST_DNS_CHECK=$(get_timestamp)
        return
    elif [ $parallel_result -eq 1 ]; then
        # 并行检测确认离线
        log_message_force "*** 状态变化: 疑似离线 -> 离线 (快速验证确认离线) ***"
        CURRENT_STATE="OFFLINE"
        return
    else
        # 检测失败（不应该发生）
        log_message "疑似离线验证失败，默认判定为离线"
        CURRENT_STATE="OFFLINE"
        return
    fi
}

# 离线状态处理（OFFLINE）- 快速登录恢复
handle_offline_state() {
    log_message_force "确认离线，立即尝试登录并进入快速恢复模式..."

    # 立即执行登录
    do_login

    # 快速恢复循环
    local offline_loop_count=0
    local last_offline_check=$(get_timestamp)
    local last_login_attempt=$(get_timestamp)
    local fast_check_interval=2  # 离线状态快速检测间隔：2秒
    local login_interval=10  # 登录间隔：10秒

    while true; do
        offline_loop_count=$((offline_loop_count + 1))
        safe_sleep $fast_check_interval

        local current_time=$(get_timestamp)
        local time_since_check=$((current_time - last_offline_check))

        # 每2秒并行检测DNS
        if [ $time_since_check -ge $fast_check_interval ]; then
            last_offline_check=$current_time

            # 并行检测DNS
            check_public_ping_parallel
            local dns_result=$?

            if [ $dns_result -eq 0 ]; then
                # DNS恢复，立即检测HTTP
                log_message "DNS检测恢复，立即验证HTTP状态..."
                check_auth_http_with_log
                local http_result=$?

                if [ $http_result -eq 0 ]; then
                    # DNS + HTTP双重验证通过，进入恢复状态
                    log_message_force "*** 状态变化: 离线 -> 恢复中 (DNS + HTTP验证通过) ***"
                    CURRENT_STATE="RECOVERING"
                    RECOVERING_SUCCESS_COUNT=0
                    return
                elif [ $http_result -eq 1 ]; then
                    # DNS在线但HTTP离线，需要继续登录
                    log_message "DNS恢复但HTTP显示离线，需要继续认证"
                    # 继续循环，下面会处理登录
                fi
            fi
        fi

        # 智能登录：DNS失败或HTTP离线时才登录
        local time_since_login=$((current_time - last_login_attempt))
        if [ $time_since_login -ge $login_interval ]; then
            if [ $((offline_loop_count % 3)) -eq 0 ]; then
                log_message "网络仍离线 (循环 #$offline_loop_count)，继续尝试登录..."
            fi
            do_login
            last_login_attempt=$current_time
        fi
    done
}

# 恢复中状态处理（RECOVERING）- 持续验证稳定性
handle_recovering_state() {
    log_message_force "进入恢复验证阶段，持续监控稳定性..."

    local recovering_check_count=0
    local required_success=5  # 需要连续5次成功才确认稳定
    local check_interval=2  # 每2秒检测一次

    while [ $recovering_check_count -lt $required_success ]; do
        recovering_check_count=$((recovering_check_count + 1))
        safe_sleep $check_interval

        # 并行检测DNS
        check_public_ping_parallel
        local dns_result=$?

        # 检测HTTP（每次都检测，确保真正在线）
        check_auth_http
        local http_result=$?

        if [ $dns_result -eq 0 ] && [ $http_result -eq 0 ]; then
            # 本次检测成功
            RECOVERING_SUCCESS_COUNT=$((RECOVERING_SUCCESS_COUNT + 1))
            log_message "恢复验证: $RECOVERING_SUCCESS_COUNT/$required_success 成功"
        else
            # 验证失败，重新进入离线状态
            log_message_force "*** 状态变化: 恢复中 -> 离线 (验证失败，网络不稳定) ***"
            RECOVERING_SUCCESS_COUNT=0
            CURRENT_STATE="OFFLINE"
            return
        fi
    done

    # 连续验证成功，确认稳定在线
    log_message_force "*** 状态变化: 恢复中 -> 在线 (连续${required_success}次验证成功，确认稳定) ***"
    CURRENT_STATE="ONLINE"
    DNS_CONSECUTIVE_FAILURES=0
    LAST_DNS_CHECK=$(get_timestamp)
    LAST_HTTP_CHECK=$(get_timestamp)
    LAST_STATUS_LOG=$(get_timestamp)
}

# 主循环
main() {
    load_config

    # 验证关键命令是否可用
    if ! check_required_commands; then
        exit 1
    fi

    # 验证配置参数
    if [ -z "$WAN_INTERFACE" ] || [ -z "$USER_ACCOUNT" ] || [ -z "$USER_PASSWORD" ]; then
        log_message "错误: 配置文件缺少必要参数"
        exit 1
    fi

    # 验证检测频率是否为有效数字
    case "$DNS_CHECK_INTERVAL" in
        ''|*[!0-9]*)
            log_message "警告: DNS_CHECK_INTERVAL无效，使用默认值10秒"
            DNS_CHECK_INTERVAL=10
            ;;
    esac

    case "$AUTH_HTTP_CHECK_INTERVAL" in
        ''|*[!0-9]*)
            log_message "警告: AUTH_HTTP_CHECK_INTERVAL无效，使用默认值60秒"
            AUTH_HTTP_CHECK_INTERVAL=60
            ;;
    esac

    case "$RECONNECT_INTERVAL" in
        ''|*[!0-9]*)
            log_message "警告: RECONNECT_INTERVAL无效，使用默认值3秒"
            RECONNECT_INTERVAL=3
            ;;
    esac

    case "$DNS_FAILURE_THRESHOLD" in
        ''|*[!0-9]*)
            log_message "警告: DNS_FAILURE_THRESHOLD无效，使用默认值2"
            DNS_FAILURE_THRESHOLD=2
            ;;
    esac

    # 确保检测频率至少为1秒
    if [ $DNS_CHECK_INTERVAL -lt 1 ]; then
        DNS_CHECK_INTERVAL=1
    fi
    if [ $AUTH_HTTP_CHECK_INTERVAL -lt 60 ]; then
        AUTH_HTTP_CHECK_INTERVAL=60
    fi
    if [ $RECONNECT_INTERVAL -lt 1 ]; then
        RECONNECT_INTERVAL=1
    fi

    log_message "=== 自动登录服务启动 (4状态自适应检测) ==="
    log_message "WAN 接口: $WAN_INTERFACE"
    log_message ""
    log_message "检测策略:"
    log_message "  • ONLINE状态: 低频轮询检测（每${DNS_CHECK_INTERVAL}秒1个DNS）"
    log_message "  • SUSPECT状态: 并行快速验证（1秒超时，所有DNS）"
    log_message "  • OFFLINE状态: 快速恢复模式（每2秒并行检测）"
    log_message "  • RECOVERING状态: 稳定性验证（连续5次成功确认）"
    log_message ""
    log_message "性能指标:"
    log_message "  • 在线误判防护: 轮询单点失败→并行快速验证"
    log_message "  • 离线发现时间: < 2秒（并行检测）"
    log_message "  • 恢复时间: < 2秒（快速检测+立即登录）"
    log_message "  • 状态稳定性: 连续5次验证防止频繁切换"
    log_message ""
    log_message "公网DNS服务器: $DNS_TEST_SERVERS"

    # 初始化时间戳
    START_TIME=$(get_timestamp)
    LAST_DNS_CHECK=0
    LAST_HTTP_CHECK=0
    LAST_STATUS_LOG=$START_TIME

    # 初始化状态为UNKNOWN，进行首次检测
    CURRENT_STATE="UNKNOWN"
    log_message "执行初始状态检测（并行快速检测）..."

    # 使用并行检测快速判定初始状态
    check_public_ping_parallel_with_log
    local initial_dns=$?

    if [ $initial_dns -eq 0 ]; then
        # DNS检测通过，检查HTTP验证
        check_auth_http_with_log
        local initial_http=$?

        if [ $initial_http -eq 0 ]; then
            log_message "初始状态: 在线 (DNS + HTTP双重验证通过)"
            CURRENT_STATE="ONLINE"
        else
            log_message "初始状态: 离线 (DNS通过但HTTP验证失败)"
            CURRENT_STATE="OFFLINE"
        fi
    else
        log_message "初始状态: 离线 (DNS检测失败)"
        CURRENT_STATE="OFFLINE"
    fi

    # 状态机主循环
    while true; do
        case "$CURRENT_STATE" in
            ONLINE)
                handle_online_state
                ;;
            SUSPECT)
                handle_suspect_state
                ;;
            OFFLINE)
                handle_offline_state
                ;;
            RECOVERING)
                handle_recovering_state
                ;;
            *)
                log_message "错误: 未知状态 $CURRENT_STATE，重置为OFFLINE"
                CURRENT_STATE="OFFLINE"
                ;;
        esac
    done
}

# 如果直接运行（不是被 source）
if [ "${0##*/}" = "login.sh" ]; then
    main
fi
EOFSCRIPT

    chmod +x "$SCRIPT_FILE"
}

# 生成配置文件
generate_config() {
    print_info "生成配置文件..."

    cat > "$CONFIG_FILE" << EOF
# 自动登录服务配置文件

# WAN 接口名称
WAN_INTERFACE="$WAN_IF"

# 登录凭证
USER_ACCOUNT="$USER_ACCOUNT"
USER_PASSWORD="$USER_PASSWORD"

# 运营商选择 (1=联通, 2=移动)
ISP_CHOICE="$ISP_CHOICE"

# 认证服务器配置
AUTH_SERVER="10.10.11.11"
AUTH_PORT_801="801"
AUTH_PORT_80="80"

# 检测频率配置 (秒)
DNS_CHECK_INTERVAL="$DNS_CHECK_INTERVAL"
AUTH_HTTP_CHECK_INTERVAL="$AUTH_HTTP_CHECK_INTERVAL"
RECONNECT_INTERVAL="$RECONNECT_INTERVAL"

# 检测策略配置
DNS_FAILURE_THRESHOLD="$DNS_FAILURE_THRESHOLD"
ONLINE_VERIFY_STRATEGY="$ONLINE_VERIFY_STRATEGY"

# 检测方法开关
ENABLE_AUTH_HTTP="$ENABLE_AUTH_HTTP"
ENABLE_PUBLIC_HTTP="$ENABLE_PUBLIC_HTTP"
ENABLE_PUBLIC_PING="$ENABLE_PUBLIC_PING"

# 公网测试服务器配置
DNS_TEST_SERVERS="$DNS_TEST_SERVERS"

# 日志配置
LOG_TYPE="$LOG_TYPE"
LOG_FILE="$LOG_FILE"
LOG_SIZE_MB="$LOG_SIZE_MB"
EOF

    chmod 600 "$CONFIG_FILE"
}

# 生成服务启动脚本
generate_service() {
    print_info "生成服务启动脚本..."

    cat > "$SERVICE_FILE" << 'EOFSERVICE'
#!/bin/sh /etc/rc.common
#
# 自动登录服务
#

START=99
STOP=15

USE_PROCD=1

PROG="/usr/local/autologin/login.sh"
NAME="autologin"

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh "$PROG"
    procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall -9 login.sh 2>/dev/null
}

reload_service() {
    stop
    start
}
EOFSERVICE

    chmod +x "$SERVICE_FILE"
}

# 启用并启动服务
enable_service() {
    print_info "启用服务..."
    "$SERVICE_FILE" enable

    print_info "启动服务..."
    "$SERVICE_FILE" start

    sleep 2

    if "$SERVICE_FILE" status >/dev/null 2>&1; then
        print_info "服务启动成功!"
    else
        print_warn "服务状态未知，请检查日志"
    fi
}

# 显示后续操作提示
show_usage() {
    echo ""
    print_info "============================================"
    print_info "  安装完成!"
    print_info "============================================"
    echo ""
    echo "服务管理命令:"
    echo "  启动服务: /etc/init.d/autologin start"
    echo "  停止服务: /etc/init.d/autologin stop"
    echo "  重启服务: /etc/init.d/autologin restart"
    echo "  查看状态: /etc/init.d/autologin status"
    echo "  开机启动: /etc/init.d/autologin enable"
    echo "  禁用启动: /etc/init.d/autologin disable"
    echo ""
    echo "配置文件:"
    echo "  配置文件: $CONFIG_FILE"
    echo "  登录脚本: $SCRIPT_FILE"
    echo ""
    if [ "$LOG_TYPE" = "1" ]; then
        echo "日志文件:"
        echo "  日志目录: $LOG_DIR"
        echo "  日志文件: $LOG_FILE"
        echo "  查看日志: tail -f $LOG_FILE"
    elif [ "$LOG_TYPE" = "2" ]; then
        echo "日志查看:"
        echo "  实时日志: logread -f | grep autologin"
        echo "  历史日志: logread | grep autologin"
    fi
    echo ""
    echo "重新配置:"
    echo "  编辑配置: vi $CONFIG_FILE"
    echo "  重启服务使配置生效"
    echo ""
}

# 主安装流程
main() {
    echo ""
    print_info "========================================"
    print_info "  OpenWrt 自动登录服务安装程序"
    print_info "========================================"
    echo ""

    check_system

    if ! check_dependencies; then
        print_error "依赖检测失败，安装终止"
        exit 1
    fi

    interactive_config
    create_directories
    generate_login_script
    generate_config
    generate_service
    enable_service
    show_usage

    print_info "安装程序执行完毕"
}

# 执行主函数
main
