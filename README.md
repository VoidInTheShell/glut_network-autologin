# 桂林理工大学南宁分校校园网自动登录服务安装脚本

</div>

> 在OpenWRT路由器上检测校园网登录状态并掉线重连，告别恶心的校园网自动掉线

**特别鸣谢[xhzLK123](https://github.com/xhzLK123)提供的登录入口**

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
### 直接执行以下命令安装
```
sh -c "$(curl -fsSLk https://gh-proxy.org/raw.githubusercontent.com/VoidInTheShell/glut_network-autologin/refs/heads/feature/install.sh)"
```

### 升级脚本
```
# 首先卸载旧版本
sh -c "$(curl -fsSLk https://gh-proxy.org/raw.githubusercontent.com/VoidInTheShell/glut_network-autologin/refs/heads/feature/uninstall.sh)"
# 然后安装新版本
sh -c "$(curl -fsSLk https://gh-proxy.org/raw.githubusercontent.com/VoidInTheShell/glut_network-autologin/refs/heads/feature/install.sh)"
```

### 命令无法执行时，使用下面的方法安装
### 1. 上传脚本到 OpenWrt

将 `install.sh` 上传到你的 OpenWrt 路由器：

```sh
# 方法1: 使用 SCP
scp install.sh root@[你的路由器IP]]:/tmp/

# 方法2: 在路由器上使用 wget下载
# 首先ssh登录到路由器
cd /tmp
wget https://gh-proxy.org/raw.githubusercontent.com/VoidInTheShell/glut_network-autologin/refs/heads/main/install.sh
```

### 2. 运行安装脚本

```sh
# SSH 登录到路由器
ssh root@[你的路由器IP]

# 添加执行权限
chmod +x /tmp/install.sh

# 运行安装程序
sh /tmp/install.sh
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

#### 3.4 检测策略配置

系统使用双层检测策略：
- **主检测**: 公网DNS Ping (快速响应，不受认证服务器限制)
- **辅助检测**: 本地认证服务器HTTP状态 (fallback验证)

注意: 认证服务器有防护机制，高频HTTP请求会被强制登出

**在线状态检测频率**:
- 公网DNS检测频率 (默认: 10秒)
- 本地HTTP检测频率 (默认: 60秒，最小60秒以避免被登出)

**离线状态重连配置**:
- 离线重连等待时间 (默认: 3秒)

**DNS离线判定策略**:
1. 任何1个DNS失败就离线 (最敏感，快速反应，可能误判)
2. 至少2个DNS失败才离线 (推荐，平衡误判和延迟)
3. 所有DNS都失败才离线 (最保守，可能延迟发现断线)

**在线判定策略**:
1. 仅依赖DNS检测 (达到DNS阈值即判定在线)
2. DNS + HTTP双重验证 (至少1个DNS可达 + 本地HTTP在线，推荐)

**公网DNS服务器配置**:
- 默认: 119.29.29.29 223.5.5.5 1.1.1.1
- 用于辅助验证网络连通性（负载均衡轮询）

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

```sh
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
**执行安装脚本会提示进行配置，无需手动配置**

编辑配置文件：

```sh
vi /etc/config/autologin
```

配置文件示例：

```sh
# WAN 接口名称
WAN_INTERFACE="eth1"

# 登录凭证
USER_ACCOUNT="your_username"
USER_PASSWORD="your_password"

# 运营商选择 (1=联通, 2=移动)
ISP_CHOICE="1"

# 认证服务器配置
AUTH_SERVER="10.10.11.11"
AUTH_PORT_801="801"
AUTH_PORT_80="80"

# 检测频率配置 (秒)
DNS_CHECK_INTERVAL="10"           # 公网DNS检测频率
AUTH_HTTP_CHECK_INTERVAL="60"     # 本地HTTP检测频率 (最小60秒)
RECONNECT_INTERVAL="3"            # 离线重连等待时间

# 检测策略配置
DNS_FAILURE_THRESHOLD="2"         # DNS离线判定阈值 (1/2/999)
ONLINE_VERIFY_STRATEGY="2"        # 在线判定策略 (1=仅DNS, 2=DNS+HTTP)

# 检测方法开关
ENABLE_AUTH_HTTP="Y"              # 启用本地认证服务器HTTP检测
ENABLE_PUBLIC_HTTP="N"            # 启用公网HTTP检测 (已废弃)
ENABLE_PUBLIC_PING="Y"            # 启用公网DNS Ping检测

# 公网测试服务器配置
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5 1.1.1.1"

# 日志配置
LOG_TYPE="1"                      # 1=文件, 2=syslog, 3=禁用
LOG_FILE="/usr/local/autologin/logs/autologin.log"
LOG_SIZE_MB="10"                  # 日志大小限制 (MB)
```

修改后重启服务使配置生效：

```sh
/etc/init.d/autologin restart
```

### 查看日志

**文件日志模式**：
```sh
# 实时查看
tail -f /usr/local/autologin/logs/autologin.log

# 查看最近 50 行
tail -n 50 /usr/local/autologin/logs/autologin.log

# 查看所有日志
cat /usr/local/autologin/logs/autologin.log
```

**syslog 模式**：
```sh
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

### 2. 四状态自适应检测机制

在线监测采用状态机设计，根据网络状态自动调整检测策略：

#### 状态 1: ONLINE (在线状态)
- **检测方式**: 低频轮询检测
- **检测频率**: 每 `DNS_CHECK_INTERVAL` 秒检测1个DNS服务器
- **特点**:
  - 轮询所有DNS服务器，分散负载
  - 不主动请求认证服务器，避免被强制下线
  - 连续失败计数机制，防止误判

#### 状态 2: SUSPECT (疑似离线)
- **触发条件**: 在线状态单次检测失败
- **检测方式**: 并行快速验证
- **检测频率**: 立即并行检测所有DNS (1秒超时)
- **转移逻辑**:
  - 验证通过 → 回到ONLINE (误报)
  - 验证失败 → 进入OFFLINE (确认离线)

#### 状态 3: OFFLINE (离线状态)
- **触发条件**: 快速验证确认网络离线
- **处理动作**:
  1. 立即执行登录请求
  2. 进入快速恢复循环
- **检测频率**:
  - DNS检测: 每2秒并行检测所有DNS
  - 登录尝试: 每10秒一次
- **转移逻辑**: DNS + HTTP双重验证通过 → 进入RECOVERING

#### 状态 4: RECOVERING (恢复验证)
- **触发条件**: DNS + HTTP双重验证初步通过
- **检测方式**: 持续稳定性验证
- **验证要求**: 连续5次成功 (每2秒检测一次)
- **转移逻辑**:
  - 连续5次成功 → 回到ONLINE (确认稳定)
  - 任意一次失败 → 回到OFFLINE (网络不稳定)

### 3. 双层检测策略

#### 主检测: 公网DNS Ping
- **优势**: 快速响应，不受认证服务器限制
- **方式**: 轮询模式 (在线状态) / 并行模式 (离线状态)
- **防护**: 连续失败判定，避免单次抖动误判

#### 辅助检测: 联通认证服务器HTTP状态码验证
- **优势**: 通过认证成功标志确认是否登录上网
- **频率**: 低频检测 (最小60秒间隔)
- **注意**: 避免高频请求导致被强制登出

### 4. 性能指标

- **在线误判防护**: 轮询单点失败 → 并行快速验证
- **离线发现时间**: < 2秒 (并行检测)
- **恢复时间**: < 2秒 (快速检测 + 立即登录)
- **状态稳定性**: 连续5次验证防止频繁切换

### 5. 日志轮转

当日志文件超过设定大小时：
1. 将当前日志重命名为 `.old` 后缀
2. 创建新的日志文件
3. 防止日志文件无限增长

### 6. 服务守护

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

```sh
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

```sh
# 方法1: 查看服务状态
/etc/init.d/autologin status

# 方法2: 查看进程
ps | grep login.sh

# 方法3: 查看日志
tail /usr/local/autologin/logs/autologin.log
```

### Q4: 日志文件太大怎么办？

编辑配置文件减小日志限制：

```sh
vi /etc/config/autologin
# 修改 LOG_SIZE_MB 为更小的值，如 5

# 重启服务
/etc/init.d/autologin restart
```

或者切换到 syslog 模式：

```sh
vi /etc/config/autologin
# 修改：
LOG_TYPE="2"
LOG_FILE="logger -t autologin"

# 重启服务
/etc/init.d/autologin restart
```

### Q5: 如何卸载？

**推荐方式：使用卸载脚本**
```sh
#直接执行以下命令卸载
sh -c "$(curl -fsSLk https://gh-proxy.org/raw.githubusercontent.com/VoidInTheShell/glut_network-autologin/refs/heads/main/uninstall.sh)"

# 上述命令无法执行时手动下载并上传 uninstall.sh 到路由器
scp uninstall.sh root@192.168.1.1:/tmp/

# SSH 登录并运行
ssh root@192.168.1.1
chmod +x /tmp/uninstall.sh && /tmp/uninstall.sh
```

卸载脚本功能：
- ✅ 自动检测安装状态
- ✅ 可选配置备份
- ✅ 安全停止所有服务和进程
- ✅ 完整清理所有文件
- ✅ 验证卸载结果
- ✅ 支持部分安装的清理

**手动卸载方式**
```sh
# 停止并禁用服务
/etc/init.d/autologin stop
/etc/init.d/autologin disable

# 删除所有文件
rm /etc/init.d/autologin
rm /etc/config/autologin
rm -rf /usr/local/autologin

# 终止残留进程
pkill -9 -f autologin
```

### Q6: 如何修改检测策略？

**修改检测频率**:
```sh
vi /etc/config/autologin

# 修改以下参数 (单位: 秒)
DNS_CHECK_INTERVAL="10"        # 在线状态DNS检测间隔
AUTH_HTTP_CHECK_INTERVAL="60"  # HTTP检测间隔 (最小60秒)
RECONNECT_INTERVAL="3"         # 离线状态重连间隔

# 重启服务
/etc/init.d/autologin restart
```

**修改离线判定策略**:
```sh
vi /etc/config/autologin

# DNS离线判定阈值
DNS_FAILURE_THRESHOLD="1"   # 1=任意1个DNS失败即离线
DNS_FAILURE_THRESHOLD="2"   # 2=至少2个DNS失败才离线 (推荐)
DNS_FAILURE_THRESHOLD="999" # 999=所有DNS都失败才离线

# 在线判定策略
ONLINE_VERIFY_STRATEGY="1"  # 1=仅依赖DNS检测
ONLINE_VERIFY_STRATEGY="2"  # 2=DNS + HTTP双重验证 (推荐)

# 重启服务
/etc/init.d/autologin restart
```

**修改DNS服务器列表**:
```sh
vi /etc/config/autologin

# 添加或修改DNS服务器 (空格分隔)
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5 1.1.1.1 114.114.114.114"

# 重启服务
/etc/init.d/autologin restart
```

### Q7: 如何调试网络检测问题？

**查看检测日志**:
```sh
# 文件日志模式
tail -f /usr/local/autologin/logs/autologin.log | grep "检测"

# syslog模式
logread -f | grep autologin | grep "检测"
```

**手动测试DNS连通性**:
```sh
# 测试DNS服务器
ping -c 1 -W 1 119.29.29.29
ping -c 1 -W 1 223.5.5.5
ping -c 1 -W 1 1.1.1.1

# 测试认证服务器
ping -c 1 -W 1 10.10.11.11
wget --timeout=2 --tries=1 -qO- http://10.10.11.11/
```

**查看当前状态**:
```sh
# 查看进程
ps | grep login.sh

# 查看最近日志
tail -n 50 /usr/local/autologin/logs/autologin.log

# 实时监控状态变化
tail -f /usr/local/autologin/logs/autologin.log | grep "状态变化"
```

## 高级配置

### 自定义检测策略

**保守策略 (避免误判，适合网络稳定场景)**:
```sh
vi /etc/config/autologin

DNS_CHECK_INTERVAL="15"         # 降低检测频率
DNS_FAILURE_THRESHOLD="999"     # 所有DNS都失败才判定离线
ONLINE_VERIFY_STRATEGY="2"      # 启用双重验证
```

**激进策略 (快速响应，适合网络不稳定场景)**:
```sh
vi /etc/config/autologin

DNS_CHECK_INTERVAL="5"          # 提高检测频率
DNS_FAILURE_THRESHOLD="1"       # 任意1个DNS失败就判定离线
ONLINE_VERIFY_STRATEGY="1"      # 仅依赖DNS检测
```

**平衡策略 (推荐，默认配置)**:
```sh
vi /etc/config/autologin

DNS_CHECK_INTERVAL="10"
DNS_FAILURE_THRESHOLD="2"
ONLINE_VERIFY_STRATEGY="2"
```

### 自定义DNS服务器列表

根据地理位置选择最快的DNS服务器:

```sh
vi /etc/config/autologin

# 国内DNS服务器 (推荐)
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5 114.114.114.114"

# 国内 + 国际DNS服务器
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5 1.1.1.1 8.8.8.8"

# 仅使用单个DNS (不推荐，无冗余)
DNS_TEST_SERVERS="119.29.29.29"
```

### 性能优化建议

**降低系统负载**:
```sh
# 1. 禁用文件日志，使用syslog
LOG_TYPE="2"

# 2. 降低检测频率
DNS_CHECK_INTERVAL="15"

# 3. 使用较少的DNS服务器
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5"
```

**最快响应速度**:
```sh
# 1. 提高检测频率
DNS_CHECK_INTERVAL="5"

# 2. 使用激进判定策略
DNS_FAILURE_THRESHOLD="1"

# 3. 使用多个DNS服务器并行检测
DNS_TEST_SERVERS="119.29.29.29 223.5.5.5 1.1.1.1"
```

### 调试模式

临时启用详细日志:

```sh
# 1. 备份当前配置
cp /etc/config/autologin /tmp/autologin.bak

# 2. 启用文件日志
vi /etc/config/autologin
LOG_TYPE="1"
LOG_FILE="/usr/local/autologin/logs/autologin.log"

# 3. 重启服务
/etc/init.d/autologin restart

# 4. 实时查看日志
tail -f /usr/local/autologin/logs/autologin.log

# 5. 调试完成后恢复配置
cp /tmp/autologin.bak /etc/config/autologin
/etc/init.d/autologin restart
```
