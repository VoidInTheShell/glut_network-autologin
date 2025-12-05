#!/bin/sh
#
# OpenWrt 自动登录服务卸载脚本
# 撤销所有安装更改，支持部分安装状态
#
set -e

INSTALL_DIR="/usr/local/autologin"
CONFIG_FILE="/etc/config/autologin"
SERVICE_FILE="/etc/init.d/autologin"
BACKUP_DIR="/tmp/autologin_backup_$(date +%Y%m%d_%H%M%S)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 显示标题
print_header() {
    echo ""
    echo -e "${BLUE}========================================"
    echo "  OpenWrt 自动登录服务卸载程序"
    echo "========================================${NC}"
    echo ""

    # 显示卸载内容说明
    echo -e "${YELLOW}🗑️  本次卸载将清理以下内容：${NC}"
    echo ""
    echo "  📁 标准文件："
    echo "     • 服务脚本: /etc/init.d/autologin"
    echo "     • 配置文件: /etc/config/autologin"
    echo "     • 安装目录: /usr/local/autologin/"
    echo ""
    echo "  📊 智能日志系统 (新版)："
    echo "     • 实时日志: /tmp/autologin/"
    echo "     • 持久化日志: /usr/local/autologin/logs/persistent.log"
    echo "     • 运行状态: /usr/local/autologin/runtime.state"
    echo ""
    echo "  🧹 临时文件："
    echo "     • HTTP检测临时文件"
    echo "     • 日志切割临时文件"
    echo "     • 备份文件"
    echo ""
    echo -e "${GREEN}💡 提示: 支持可选配置备份，建议备份后再卸载${NC}"
    echo ""
}

# 检测安装状态
check_installation() {
    print_step "检测安装状态..."

    local installed=0
    local status=""

    # 检查服务文件
    if [ -f "$SERVICE_FILE" ]; then
        status="${status}  ✓ 服务脚本: $SERVICE_FILE\n"
        installed=1
    else
        status="${status}  ✗ 服务脚本: 未安装\n"
    fi

    # 检查配置文件
    if [ -f "$CONFIG_FILE" ]; then
        status="${status}  ✓ 配置文件: $CONFIG_FILE\n"
        installed=1
    else
        status="${status}  ✗ 配置文件: 未安装\n"
    fi

    # 检查安装目录
    if [ -d "$INSTALL_DIR" ]; then
        status="${status}  ✓ 安装目录: $INSTALL_DIR\n"
        installed=1
    else
        status="${status}  ✗ 安装目录: 未安装\n"
    fi

    # 检查服务状态
    if [ -f "$SERVICE_FILE" ]; then
        if "$SERVICE_FILE" enabled 2>/dev/null; then
            status="${status}  ✓ 开机自启: 已启用\n"
        else
            status="${status}  ✗ 开机自启: 未启用\n"
        fi

        if pgrep -f "/usr/local/autologin/login.sh" >/dev/null 2>&1; then
            status="${status}  ✓ 服务状态: 运行中\n"
        else
            status="${status}  ✗ 服务状态: 未运行\n"
        fi
    fi

    echo ""
    echo "当前安装状态:"
    echo -e "$status"

    if [ $installed -eq 0 ]; then
        print_warn "未检测到安装的组件"
        echo ""
        read -p "是否清理可能残留的文件? (y/n): " cleanup_anyway
        if [ "$cleanup_anyway" != "y" ] && [ "$cleanup_anyway" != "Y" ]; then
            print_info "卸载已取消"
            exit 0
        fi
    fi

    # 不返回值，避免与set -e冲突
}

# 确认卸载
confirm_uninstall() {
    echo ""
    print_warn "警告: 此操作将删除所有相关文件和配置"
    echo ""
    echo "将要删除的内容:"
    echo "  - 服务脚本: $SERVICE_FILE"
    echo "  - 配置文件: $CONFIG_FILE"
    echo "  - 安装目录: $INSTALL_DIR"
    echo "  - 所有日志文件"
    echo ""

    read -p "是否要备份配置文件? (y/n) [推荐: y]: " do_backup
    if [ "$do_backup" = "y" ] || [ "$do_backup" = "Y" ]; then
        BACKUP_ENABLED=1
    else
        BACKUP_ENABLED=0
    fi

    echo ""
    read -p "确认卸载? (yes/no): " confirm
    if [ "$confirm" != "yes" ] && [ "$confirm" != "YES" ]; then
        print_info "卸载已取消"
        exit 0
    fi
}

# 备份配置
backup_config() {
    if [ $BACKUP_ENABLED -eq 1 ]; then
        print_step "备份配置文件..."

        mkdir -p "$BACKUP_DIR"

        # 备份配置文件
        if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$BACKUP_DIR/"
            print_info "已备份: $CONFIG_FILE"
        fi

        # 备份日志文件（如果存在且不太大）
        if [ -d "$INSTALL_DIR/logs" ]; then
            local log_size=$(du -sm "$INSTALL_DIR/logs" 2>/dev/null | cut -f1)
            if [ -n "$log_size" ] && [ "$log_size" -lt 50 ]; then
                cp -r "$INSTALL_DIR/logs" "$BACKUP_DIR/" 2>/dev/null || true
                print_info "已备份: 日志文件"
            else
                print_warn "日志文件过大(${log_size}MB)，跳过备份"
            fi
        fi

        print_info "备份位置: $BACKUP_DIR"
    else
        print_info "跳过备份"
    fi
}

# 停止服务
stop_service() {
    print_step "停止服务..."

    # 尝试使用服务脚本停止
    if [ -f "$SERVICE_FILE" ]; then
        print_info "使用服务脚本停止服务..."
        if "$SERVICE_FILE" stop 2>/dev/null; then
            print_info "服务已通过脚本停止"
            sleep 2
        else
            print_warn "服务脚本停止失败，尝试强制终止进程"
        fi
    else
        print_info "服务脚本不存在，直接终止进程"
    fi

    # 强制终止所有login.sh进程
    local pids=$(pgrep -f "/usr/local/autologin/login.sh" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        print_info "终止login.sh进程: $pids"
        kill -15 $pids 2>/dev/null || true  # 先尝试优雅终止
        sleep 2

        # 检查是否还有残留进程，强制kill
        pids=$(pgrep -f "/usr/local/autologin/login.sh" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            print_warn "进程未响应SIGTERM，使用SIGKILL强制终止: $pids"
            kill -9 $pids 2>/dev/null || true
            sleep 1
        fi
    fi

    # 额外检查：终止所有包含autologin的进程
    local autologin_pids=$(pgrep -f "autologin" 2>/dev/null || true)
    if [ -n "$autologin_pids" ]; then
        print_info "终止其他autologin相关进程: $autologin_pids"
        kill -9 $autologin_pids 2>/dev/null || true
        sleep 1
    fi

    # 最终验证进程是否已终止
    if pgrep -f "/usr/local/autologin/login.sh" >/dev/null 2>&1; then
        print_error "警告: 部分进程可能仍在运行"
        local remaining=$(pgrep -af "/usr/local/autologin" 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            print_error "残留进程详情:"
            echo "$remaining" | while read -r line; do
                echo "  $line"
            done
        fi
    else
        print_info "所有进程已成功终止"
    fi
}

# 禁用开机自启动
disable_autostart() {
    print_step "禁用开机自启动..."

    if [ -f "$SERVICE_FILE" ]; then
        if "$SERVICE_FILE" disable 2>/dev/null; then
            print_info "开机自启动已禁用"
        else
            print_warn "禁用自启动失败（可能未启用）"
        fi
    else
        print_info "服务文件不存在，跳过"
    fi
}

# 删除文件
remove_files() {
    print_step "删除文件..."

    local removed=0

    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        print_info "已删除: $SERVICE_FILE"
        removed=1
    fi

    # 删除 rc.d 中的符号链接（OpenWrt 自启动机制）
    local rc_links=$(find /etc/rc.d -name '*autologin' 2>/dev/null || true)
    if [ -n "$rc_links" ]; then
        echo "$rc_links" | while read -r link; do
            rm -f "$link"
            print_info "已删除: $link"
        done
        removed=1
    fi

    # 删除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        print_info "已删除: $CONFIG_FILE"
        removed=1
    fi

    # 删除安装目录（包括持久化日志和runtime.state）
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_info "已删除: $INSTALL_DIR (包括持久化日志和runtime.state)"
        removed=1
    fi

    # 删除实时日志目录（/tmp/autologin）
    if [ -d "/tmp/autologin" ]; then
        rm -rf "/tmp/autologin"
        print_info "已删除: /tmp/autologin (实时日志)"
        removed=1
    fi

    if [ $removed -eq 0 ]; then
        print_warn "没有找到需要删除的文件"
    fi
}

# 清理残留
cleanup_residuals() {
    print_step "清理残留..."

    local cleaned=0

    # 检查是否有残留的进程
    if pgrep -f "autologin" >/dev/null 2>&1; then
        print_warn "发现残留进程，尝试清理..."
        pkill -9 -f "autologin" 2>/dev/null || true
        cleaned=1
    fi

    # 检查是否有残留的login.sh进程（可能使用不同的进程名）
    if pgrep -f "/usr/local/autologin/login.sh" >/dev/null 2>&1; then
        print_warn "发现login.sh进程，强制终止..."
        pkill -9 -f "/usr/local/autologin/login.sh" 2>/dev/null || true
        cleaned=1
    fi

    # 清理临时文件 - autologin备份目录（除了当前备份）
    local temp_files=$(find /tmp -maxdepth 1 -name "autologin_backup_*" 2>/dev/null | grep -v "$BACKUP_DIR" || true)
    if [ -n "$temp_files" ]; then
        print_info "清理旧备份文件..."
        echo "$temp_files" | while read -r file; do
            rm -rf "$file" 2>/dev/null || true
        done
        cleaned=1
    fi

    # 清理运行时脚本产生的临时文件
    local auth_temp_files=$(find /tmp -maxdepth 1 -name "auth_http_check.*" 2>/dev/null || true)
    if [ -n "$auth_temp_files" ]; then
        print_info "清理HTTP检测临时文件..."
        echo "$auth_temp_files" | while read -r file; do
            rm -f "$file" 2>/dev/null || true
        done
        cleaned=1
    fi

    # 清理智能日志系统产生的临时文件
    local fault_temp_files=$(find /tmp -maxdepth 1 -name "fault_events_*" 2>/dev/null || true)
    if [ -n "$fault_temp_files" ]; then
        print_info "清理故障事件临时文件..."
        echo "$fault_temp_files" | while read -r file; do
            rm -f "$file" 2>/dev/null || true
        done
        cleaned=1
    fi

    local persistent_temp_files=$(find /tmp -maxdepth 1 -name "persistent_trim_*" 2>/dev/null || true)
    if [ -n "$persistent_temp_files" ]; then
        print_info "清理持久化日志临时文件..."
        echo "$persistent_temp_files" | while read -r file; do
            rm -f "$file" 2>/dev/null || true
        done
        cleaned=1
    fi

    # 检测并清理不兼容的旧版本日志
    print_info "检测不兼容的旧版本日志..."
    local old_log_found=0

    # 检查旧版本的日志文件（没有智能日志系统的版本）
    if [ -f "/usr/local/autologin/logs/autologin.log.old" ]; then
        print_warn "发现旧版本日志备份: /usr/local/autologin/logs/autologin.log.old"
        rm -f "/usr/local/autologin/logs/autologin.log.old" 2>/dev/null || true
        old_log_found=1
        cleaned=1
    fi

    if [ -f "/usr/local/autologin/logs/autologin.log" ]; then
        # 检查是否为旧版本日志（没有[LEVEL]标记）
        if ! grep -q '\[OFFLINE\]\|\[AUTH\]\|\[STAT\]' "/usr/local/autologin/logs/autologin.log" 2>/dev/null; then
            print_warn "发现不兼容的旧版本日志格式: /usr/local/autologin/logs/autologin.log"
            old_log_found=1
        fi
    fi

    if [ $old_log_found -eq 1 ]; then
        print_info "旧版本日志文件已清理或将随安装目录一起删除"
        print_info "新版本使用智能双层日志架构，不兼容旧日志格式"
    fi

    if [ $cleaned -eq 0 ]; then
        print_info "无残留文件需要清理"
    else
        print_info "残留清理完成"
    fi
}

# 验证卸载
verify_uninstall() {
    print_step "验证卸载..."

    local failed=0
    local status=""

    # 检查服务文件
    if [ -f "$SERVICE_FILE" ]; then
        status="${status}  ${RED}✗ 服务文件仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 服务文件已删除${NC}\n"
    fi

    # 检查配置文件
    if [ -f "$CONFIG_FILE" ]; then
        status="${status}  ${RED}✗ 配置文件仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 配置文件已删除${NC}\n"
    fi

    # 检查安装目录
    if [ -d "$INSTALL_DIR" ]; then
        status="${status}  ${RED}✗ 安装目录仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 安装目录已删除${NC}\n"
    fi

    # 检查实时日志目录
    if [ -d "/tmp/autologin" ]; then
        status="${status}  ${RED}✗ 实时日志目录仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 实时日志目录已删除${NC}\n"
    fi

    # 检查进程
    if pgrep -f "/usr/local/autologin" >/dev/null 2>&1; then
        status="${status}  ${RED}✗ 进程仍在运行${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 所有进程已终止${NC}\n"
    fi

    # 检查 rc.d 符号链接
    local rc_link_count=$(find /etc/rc.d -name '*autologin' 2>/dev/null | wc -l)
    if [ "$rc_link_count" -gt 0 ]; then
        status="${status}  ${RED}✗ rc.d 符号链接仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ rc.d 符号链接已删除${NC}\n"
    fi

    # 检查临时文件残留
    local temp_count=$(find /tmp -maxdepth 1 \( -name "auth_http_check.*" -o -name "fault_events_*" -o -name "persistent_trim_*" \) 2>/dev/null | wc -l)
    if [ "$temp_count" -gt 0 ]; then
        status="${status}  ${YELLOW}⚠ 发现 $temp_count 个临时文件残留${NC}\n"
        # 临时文件残留不算严重失败，只是警告
    else
        status="${status}  ${GREEN}✓ 临时文件已清理${NC}\n"
    fi

    echo ""
    echo "卸载验证结果:"
    echo -e "$status"

    return $failed
}

# 显示卸载结果
show_result() {
    local exit_code=$1

    echo ""
    if [ $exit_code -eq 0 ]; then
        print_info "========================================="
        print_info "  卸载成功!"
        print_info "========================================="
        echo ""

        if [ $BACKUP_ENABLED -eq 1 ]; then
            echo "配置备份位置: $BACKUP_DIR"
            echo ""
            echo "如需恢复配置:"
            echo "  1. 重新运行 install.sh"
            echo "  2. 从备份恢复配置: cp $BACKUP_DIR/autologin /etc/config/"
            echo "  3. 重启服务: /etc/init.d/autologin restart"
            echo ""
            echo "注意: 新版本使用DNS轮询检测，配置参数可能需要调整"
        else
            echo "如需重新安装，请运行: bash install.sh"
            echo ""
            echo "新版本改进:"
            echo "  • DNS轮询检测 - 降低对公网DNS服务器的请求频率"
            echo "  • 连续失败判定 - 2次连续失败才判定离线，减少误判"
            echo "  • 在线状态保护 - 不主动请求认证服务器，避免被强制下线"
        fi

        echo ""
        print_info "卸载程序执行完毕"
    else
        print_error "========================================="
        print_error "  卸载未完全成功"
        print_error "========================================="
        echo ""
        echo "请检查上述错误信息，可能需要手动清理残留文件"
        echo ""
        echo "手动清理命令:"
        echo "  # 停止所有相关进程"
        echo "  pkill -9 -f autologin"
        echo "  pkill -9 -f /usr/local/autologin/login.sh"
        echo ""
        echo "  # 删除文件和目录"
        echo "  rm -f $SERVICE_FILE"
        echo "  rm -f $CONFIG_FILE"
        echo "  rm -rf $INSTALL_DIR"
        echo "  rm -f /etc/rc.d/*autologin*"
        echo ""
        echo "  # 清理临时文件"
        echo "  rm -f /tmp/auth_http_check.*"
        echo "  rm -rf /tmp/autologin_backup_*"
        echo ""
        echo "  # 禁用自启动（如果服务文件存在）"
        echo "  /etc/init.d/autologin disable 2>/dev/null || true"
    fi

    echo ""
}

# 主函数
main() {
    BACKUP_ENABLED=0

    print_header

    # 检测安装状态
    check_installation

    # 确认卸载
    confirm_uninstall

    echo ""
    print_info "开始卸载..."
    echo ""

    # 备份配置
    backup_config

    # 停止服务
    stop_service

    # 禁用自启动
    disable_autostart

    # 删除文件
    remove_files

    # 清理残留
    cleanup_residuals

    # 验证卸载
    if verify_uninstall; then
        show_result 0
        exit 0
    else
        show_result 1
        exit 1
    fi
}

# 执行主函数
main
