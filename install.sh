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

    # 检测频率
    read -p "请输入网络检测频率 (毫秒) [默认: 30000]: " CHECK_INTERVAL
    CHECK_INTERVAL=${CHECK_INTERVAL:-30000}

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
    echo "  检测频率: $CHECK_INTERVAL ms ($((CHECK_INTERVAL/1000))秒)"
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
# 自动登录脚本
# 由安装程序自动生成
#

# 配置文件
CONFIG_FILE="/etc/config/autologin"

# ============ 命令兼容性检测 ============
# 检查命令是否可用
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证关键命令
check_required_commands() {
    local missing=""
    for cmd in ip ifconfig ping wget sleep; do
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
            log_message "警告: sleep参数无效 ($seconds), 使用默认值30秒"
            seconds=30
            ;;
    esac
    # 确保至少sleep 1秒
    if [ "$seconds" -lt 1 ]; then
        seconds=1
    fi
    sleep "$seconds"
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

# 执行登录请求
do_login() {
    local current_ip=$(get_wan_ip)
    local mac_address=$(get_wan_mac)

    if [ -z "$current_ip" ]; then
        log_message "错误: 无法获取 WAN 口 IP 地址 (接口: $WAN_INTERFACE)"
        return 1
    fi

    log_message "当前 IP: $current_ip, MAC: $mac_address"

    # 构建登录 URL
    local url="http://10.10.11.11:801/eportal/portal/login?callback=dr1003&login_method=1&user_account=%2C0%2C${USER_ACCOUNT}&user_password=${USER_PASSWORD}&wlan_user_ip=${current_ip}&wlan_user_ipv6=&wlan_user_mac=000000000000&wlan_ac_ip=&wlan_ac_name=&page_index=pMnaGv1756888844&authex_enable=${ISP_CHOICE}&jsVersion=4.2.1&terminal_type=1&lang=zh-cn&lang=zh"

    # 执行登录请求
    local response=$(wget -qO- --timeout=10 "$url" 2>&1)
    log_message "登录响应: $response"

    return 0
}

# 检查网络连接
check_network() {
    # 使用多个 DNS 服务器进行测试
    local test_hosts="119.29.29.29 223.5.5.5 8.8.8.8"

    for host in $test_hosts; do
        if ping -c 1 -W 3 "$host" > /dev/null 2>&1; then
            return 0
        fi
    done

    return 1
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

    # 验证CHECK_INTERVAL是否为有效数字
    case "$CHECK_INTERVAL" in
        ''|*[!0-9]*)
            log_message "警告: CHECK_INTERVAL无效，使用默认值30000ms"
            CHECK_INTERVAL=30000
            ;;
    esac

    log_message "=== 自动登录服务启动 ==="
    log_message "WAN 接口: $WAN_INTERFACE"
    log_message "检测频率: $CHECK_INTERVAL ms"

    while true; do
        if ! check_network; then
            log_message "网络连接失败，尝试重新登录..."
            do_login

            # 等待10秒后重新检查
            safe_sleep 10

            if check_network; then
                log_message "网络连接已恢复"
            else
                log_message "网络仍然无法连接，将在下次循环重试"
            fi
        fi

        # 等待指定的检测间隔（转换毫秒为秒，busybox sleep只支持整数）
        local sleep_seconds=$((CHECK_INTERVAL / 1000))
        if [ $sleep_seconds -lt 1 ]; then
            sleep_seconds=1
        fi
        safe_sleep $sleep_seconds
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

# 检测频率 (毫秒)
CHECK_INTERVAL="$CHECK_INTERVAL"

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
