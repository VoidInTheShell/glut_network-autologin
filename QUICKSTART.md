# 快速使用指南

## 一键安装（3步完成）

### 步骤 1: 上传脚本

```bash
# 通过 SCP 上传（在你的电脑上执行）
scp install.sh root@192.168.1.1:/tmp/

# 或者在路由器上直接下载
ssh root@192.168.1.1
wget http://your-server/install.sh -O /tmp/install.sh
```

### 步骤 2: 运行安装

```bash
# SSH 登录路由器
ssh root@192.168.1.1

# 运行安装脚本
chmod +x /tmp/install.sh && /tmp/install.sh
```

### 步骤 3: 按提示配置

安装程序会询问：
1. **WAN 接口** - 自动检测，按回车确认即可
2. **登录账号** - 输入你的账号
3. **登录密码** - 输入密码（不显示）
4. **运营商** - 选 1（联通）或 2（移动）
5. **检测频率** - 默认 30000 毫秒，直接回车
6. **日志方式** - 推荐选 1（文件日志）
7. **日志大小** - 默认 10 MB，直接回车

完成！服务已自动启动并设置开机自启。

---

## 常用命令

```bash
# 重启服务
/etc/init.d/autologin restart

# 查看日志
tail -f /usr/local/autologin/logs/autologin.log

# 修改配置
vi /etc/config/autologin

# 查看状态
/etc/init.d/autologin status
```

---

## 配置说明

安装后配置文件位于：`/etc/config/autologin`

```bash
# 修改检测频率为 60 秒
CHECK_INTERVAL="60000"

# 修改运营商
ISP_CHOICE="2"  # 改为移动

# 修改账号密码
USER_ACCOUNT="new_account"
USER_PASSWORD="new_password"
```

修改后重启服务：`/etc/init.d/autologin restart`

---

## 配置示例

### 示例 1: 默认配置（推荐）

- WAN 接口：自动检测
- 检测频率：30 秒
- 日志方式：文件（10 MB）

```bash
# 安装时一路回车即可
```

### 示例 2: 高频检测 + Syslog

- 检测频率：10 秒（10000 毫秒）
- 日志方式：syslog（系统日志）

```bash
# 安装时输入：
检测频率: 10000
日志方式: 2
```

查看日志：`logread -f | grep autologin`

### 示例 3: 低频检测 + 小日志

- 检测频率：60 秒（60000 毫秒）
- 日志大小：5 MB

```bash
# 安装时输入：
检测频率: 60000
日志方式: 1
日志大小: 5
```

---

## 故障排查

### 问题 1: 服务无法启动

```bash
# 检查配置文件
cat /etc/config/autologin

# 手动运行测试
/usr/local/autologin/login.sh
```

### 问题 2: 无法自动登录

```bash
# 查看日志找错误
tail -n 50 /usr/local/autologin/logs/autologin.log

# 检查 WAN 接口是否正确
ifconfig
uci show network.wan
```

### 问题 3: 日志文件太大

```bash
# 清空日志
> /usr/local/autologin/logs/autologin.log

# 或调小日志限制
vi /etc/config/autologin
# LOG_SIZE_MB="5"

/etc/init.d/autologin restart
```

---

## 卸载方法

```bash
# 停止服务
/etc/init.d/autologin stop
/etc/init.d/autologin disable

# 删除文件
rm /etc/init.d/autologin
rm /etc/config/autologin
rm -rf /usr/local/autologin
```

---

详细文档请参考：[README.md](README.md)
