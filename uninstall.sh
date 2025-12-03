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

    return $installed
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
        if "$SERVICE_FILE" stop 2>/dev/null; then
            print_info "服务已停止"
        else
            print_warn "服务脚本停止失败，尝试强制终止进程"
        fi
    fi

    # 强制终止所有相关进程
    local pids=$(pgrep -f "/usr/local/autologin/login.sh" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        print_info "终止进程: $pids"
        kill -9 $pids 2>/dev/null || true
        sleep 1
    fi

    # 验证进程是否已终止
    if pgrep -f "/usr/local/autologin/login.sh" >/dev/null 2>&1; then
        print_error "警告: 部分进程可能仍在运行"
    else
        print_info "所有进程已终止"
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

    # 删除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        print_info "已删除: $CONFIG_FILE"
        removed=1
    fi

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_info "已删除: $INSTALL_DIR"
        removed=1
    fi

    if [ $removed -eq 0 ]; then
        print_warn "没有找到需要删除的文件"
    fi
}

# 清理残留
cleanup_residuals() {
    print_step "清理残留..."

    # 检查是否有残留的进程
    if pgrep -f "autologin" >/dev/null 2>&1; then
        print_warn "发现残留进程，尝试清理..."
        pkill -9 -f "autologin" 2>/dev/null || true
    fi

    # 检查是否有残留的临时文件
    if [ -d "/tmp/autologin"* 2>/dev/null ]; then
        print_info "清理临时文件..."
        rm -rf /tmp/autologin* 2>/dev/null || true
    fi

    print_info "清理完成"
}

# 验证卸载
verify_uninstall() {
    print_step "验证卸载..."

    local failed=0
    local status=""

    if [ -f "$SERVICE_FILE" ]; then
        status="${status}  ${RED}✗ 服务文件仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 服务文件已删除${NC}\n"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        status="${status}  ${RED}✗ 配置文件仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 配置文件已删除${NC}\n"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        status="${status}  ${RED}✗ 安装目录仍存在${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 安装目录已删除${NC}\n"
    fi

    if pgrep -f "/usr/local/autologin" >/dev/null 2>&1; then
        status="${status}  ${RED}✗ 进程仍在运行${NC}\n"
        failed=1
    else
        status="${status}  ${GREEN}✓ 所有进程已终止${NC}\n"
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
        else
            echo "如需重新安装，请运行: bash install.sh"
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
        echo "  rm -f $SERVICE_FILE"
        echo "  rm -f $CONFIG_FILE"
        echo "  rm -rf $INSTALL_DIR"
        echo "  pkill -9 -f autologin"
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
