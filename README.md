# 桂林理工大学南宁分校校园网自动登录服务安装程序

## 功能特性

- ✅ 自动检测 OpenWrt 系统环境
- ✅ 自动安装缺失的依赖包（wget、curl）
- ✅ 自动获取 WAN 口本地 DHCP IP（无需手动指定接口）
- ✅ 交互式配置（账号、密码、检测频率、日志选项）
- ✅ 灵活的日志管理（文件日志、syslog、禁用）
- ✅ 日志大小限制和自动轮转
- ✅ 自动配置为 OpenWrt 系统服务
- ✅ 支持开机自启动
- ✅ 网络断线自动重连

## 快速开始

### 1. 上传脚本到 OpenWrt

将 `install.sh` 上传到你的 OpenWrt 路由器：

```bash
# 方法1: 使用 SCP
scp install.sh root@192.168.1.1:/tmp/

# 方法2: 在路由器上使用 wget
ssh root@192.168.1.1
cd /tmp
wget http://your-server/install.sh
```

### 2. 运行安装脚本

```bash
# SSH 登录到路由器
ssh root@192.168.1.1

# 添加执行权限
chmod +x /tmp/install.sh

# 运行安装程序
/tmp/install.sh
```

### 3. 按照提示配置

安装程序会引导你完成以下配置：

#### 3.1 WAN 接口配置
- 脚本会自动检测 WAN 接口（如 eth1、wan 等）
- 如果检测正确，直接按回车确认
- 如果需要手动指定，输入正确的接口名称

#### 3.2 登录凭证
- 输入登录账号
- 输入登录密码（输入时不显示）

#### 3.3 运营商选择
- 1 = 联通
- 2 = 移动

#### 3.4 检测频率
- 单位：毫秒（ms）
- 默认：30000 ms（30秒）
- 建议范围：10000 - 60000 ms

#### 3.5 日志配置
选择日志输出方式：

**选项 1: 输出到文件**
- 日志文件路径：`/usr/local/autologin/logs/autologin.log`
- 可设置日志大小限制（默认 10 MB）
- 超过限制自动轮转（保留 .old 文件）
- 查看日志：`tail -f /usr/local/autologin/logs/autologin.log`

**选项 2: 输出到 syslog**
- 日志输出到系统日志
- 实时查看：`logread -f | grep autologin`
- 历史日志：`logread | grep autologin`

**选项 3: 不记录日志**
- 所有日志输出到 /dev/null
- 适合性能敏感场景

## 安装后管理

### 服务管理命令

```bash
# 启动服务
/etc/init.d/autologin start

# 停止服务
/etc/init.d/autologin stop

# 重启服务
/etc/init.d/autologin restart

# 查看状态
/etc/init.d/autologin status

# 启用开机自启动
/etc/init.d/autologin enable

# 禁用开机自启动
/etc/init.d/autologin disable
```

### 修改配置

编辑配置文件：

```bash
vi /etc/config/autologin
```

配置文件示例：

```bash
# WAN 接口名称
WAN_INTERFACE="eth1"

# 登录凭证
USER_ACCOUNT="your_username"
USER_PASSWORD="your_password"

# 运营商选择 (1=联通, 2=移动)
ISP_CHOICE="1"

# 检测频率 (毫秒)
CHECK_INTERVAL="30000"

# 日志配置
LOG_TYPE="1"
LOG_FILE="/usr/local/autologin/logs/autologin.log"
LOG_SIZE_MB="10"
```

修改后重启服务使配置生效：

```bash
/etc/init.d/autologin restart
```

### 查看日志

**文件日志模式**：
```bash
# 实时查看
tail -f /usr/local/autologin/logs/autologin.log

# 查看最近 50 行
tail -n 50 /usr/local/autologin/logs/autologin.log

# 查看所有日志
cat /usr/local/autologin/logs/autologin.log
```

**syslog 模式**：
```bash
# 实时查看
logread -f | grep autologin

# 查看历史
logread | grep autologin
```

## 工作原理

### 1. WAN 口 IP 自动获取

脚本使用多种方法自动获取 WAN 口的本地 DHCP IP：

1. 优先使用 `ip addr` 命令（现代系统）
2. 其次使用 `ifconfig` 命令（兼容旧系统）
3. 支持多种 IP 格式解析

### 2. 网络监测机制

- 定期 ping 测试服务器（119.29.29.29、223.5.5.5、8.8.8.8）
- 如果网络不通，自动执行登录请求
- 登录后再次检测，确认网络恢复
- 循环监测，保持网络在线

### 3. 日志轮转

当日志文件超过设定大小时：
1. 将当前日志重命名为 `.old` 后缀
2. 创建新的日志文件
3. 防止日志文件无限增长

### 4. 服务守护

使用 OpenWrt 的 `procd` 进程管理器：
- 自动重启崩溃的进程
- 开机自动启动
- 优雅的服务管理

## 文件结构

安装完成后的文件分布：

```
/etc/
├── config/
│   └── autologin              # 配置文件
└── init.d/
    └── autologin              # 服务启动脚本

/usr/local/autologin/
├── login.sh                   # 登录主脚本
└── logs/                      # 日志目录（如果启用文件日志）
    ├── autologin.log          # 当前日志
    └── autologin.log.old      # 轮转后的旧日志
```

## 常见问题

### Q1: 如何查看 WAN 接口名称？

```bash
# 方法1: 查看网络接口
ifconfig

# 方法2: 查看 UCI 配置
uci show network.wan

# 方法3: 查看路由表
ip route | grep default
```

### Q2: 服务无法启动？

检查以下几点：
1. 确认配置文件存在：`cat /etc/config/autologin`
2. 确认脚本有执行权限：`ls -l /usr/local/autologin/login.sh`
3. 查看系统日志：`logread | tail -20`
4. 手动运行测试：`/usr/local/autologin/login.sh`

### Q3: 如何确认服务在运行？

```bash
# 方法1: 查看服务状态
/etc/init.d/autologin status

# 方法2: 查看进程
ps | grep login.sh

# 方法3: 查看日志
tail /usr/local/autologin/logs/autologin.log
```

### Q4: 日志文件太大怎么办？

编辑配置文件减小日志限制：

```bash
vi /etc/config/autologin
# 修改 LOG_SIZE_MB 为更小的值，如 5

# 重启服务
/etc/init.d/autologin restart
```

或者切换到 syslog 模式：

```bash
vi /etc/config/autologin
# 修改：
LOG_TYPE="2"
LOG_FILE="logger -t autologin"

# 重启服务
/etc/init.d/autologin restart
```

### Q5: 如何卸载？

```bash
# 停止并禁用服务
/etc/init.d/autologin stop
/etc/init.d/autologin disable

# 删除服务文件
rm /etc/init.d/autologin

# 删除配置文件
rm /etc/config/autologin

# 删除程序目录
rm -rf /usr/local/autologin
```

### Q6: 如何修改检测频率？

编辑配置文件：

```bash
vi /etc/config/autologin
# 修改 CHECK_INTERVAL 值（单位：毫秒）
# 例如：60000 = 60秒检测一次

# 重启服务
/etc/init.d/autologin restart
```

## 高级配置

### 自定义登录 URL

如果你的认证服务器地址不是 `10.10.11.11`，需要修改登录脚本：

```bash
vi /usr/local/autologin/login.sh

# 找到构建 URL 的部分，修改服务器地址
local url="http://YOUR_SERVER_IP:801/eportal/portal/login?..."
```

### 添加多个检测服务器

编辑登录脚本：

```bash
vi /usr/local/autologin/login.sh

# 找到 check_network 函数，添加更多测试主机
local test_hosts="119.29.29.29 223.5.5.5 8.8.8.8 114.114.114.114"
```

### 日志输出到远程服务器

使用 syslog 模式 + 远程日志服务器：

```bash
# 配置远程 syslog
vi /etc/config/system

config system
    option log_ip '192.168.1.100'
    option log_port '514'
    option log_proto 'udp'

# 重启 syslog
/etc/init.d/log restart
```

## 技术支持

- 原始脚本位置：`F:\0.00.Project\1.25.12.LoginAutoSH\login.sh`
- 安装脚本位置：`F:\0.00.Project\1.25.12.LoginAutoSH\install.sh`

## 许可证

本脚本仅供学习和个人使用。使用者需遵守当地网络使用规定。

## 更新日志

### v1.0.0
- 初始版本
- 自动检测环境和安装依赖
- 自动获取 WAN 口 IP
- 交互式配置向导
- 支持文件日志和 syslog
- 日志大小限制和轮转
- OpenWrt 服务集成
