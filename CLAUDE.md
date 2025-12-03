# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an OpenWrt automatic campus network login service for Guilin University of Technology Nanning Campus. The project automates network authentication by detecting connection status and re-authenticating when needed.

**Target platform**: OpenWrt routers
**Authentication server**: `10.10.11.11:801` (campus network portal)

## Key Architecture

### Three-Script System

1. **install.sh** - Main installer (recommended entry point)
   - Interactive configuration wizard
   - Automatic dependency installation (wget, curl)
   - Auto-detects WAN interface via UCI/ip route/ifconfig
   - Generates runtime script, config file, and OpenWrt service
   - Installs to `/usr/local/autologin/`

2. **uninstall.sh** - Complete uninstaller
   - Detects installation status (supports partial installations)
   - Optional configuration backup with timestamp
   - Safely stops all services and processes
   - Removes all files and directories
   - Verifies uninstall completeness
   - Provides detailed uninstall report

3. **login.sh** (root directory) - Original legacy script (DEPRECATED)
   - Kept for reference only
   - Uses hardcoded credentials and WAN interface
   - New installations should NOT use this file

4. **test.sh** - Pre-installation diagnostic tool
   - Tests system environment, dependencies, network interfaces
   - Optional login endpoint testing
   - Provides configuration recommendations

### Runtime Architecture

After installation, the system creates:
- `/usr/local/autologin/login.sh` - Generated runtime script (different from root login.sh)
- `/etc/config/autologin` - Configuration file
- `/etc/init.d/autologin` - OpenWrt procd service script

The runtime script (`/usr/local/autologin/login.sh`) operates as:
- Infinite loop checking network connectivity via ping to DNS servers (119.29.29.29, 223.5.5.5, 8.8.8.8)
- On connection failure: Fetches WAN IP dynamically and sends authentication request
- Configurable check interval (default 30000ms)
- Three logging modes: file (with rotation), syslog, or disabled

## Important Technical Details

### Busybox Compatibility

**CRITICAL**: OpenWrt uses busybox versions of standard commands with limited features:

1. **sleep command**: Only accepts integer seconds, NOT decimals
   - ❌ WRONG: `sleep 30.5` or `sleep $(echo "30000/1000" | bc)`
   - ✅ CORRECT: `sleep $((30000/1000))` or use `safe_sleep` function

2. **Avoid bc dependency**: Use shell arithmetic instead
   - ❌ WRONG: `echo "scale=3; $CHECK_INTERVAL/1000" | bc`
   - ✅ CORRECT: `$((CHECK_INTERVAL/1000))`

3. **Runtime script includes automatic error detection**:
   - `command_exists()` - Check if command is available
   - `check_required_commands()` - Validate critical commands at startup
   - `safe_sleep()` - Validates numeric input and ensures proper integer sleep

### WAN IP Detection Strategy

The runtime script tries multiple methods to get the WAN interface IP:
1. `ip addr show dev $WAN_INTERFACE` (modern)
2. `ifconfig $WAN_INTERFACE` (legacy compatibility)
3. Regex parsing of ifconfig output

This is critical because the campus network requires the current DHCP IP in the authentication URL.

### Authentication URL Structure

```
http://10.10.11.11:801/eportal/portal/login?
  callback=dr1003
  &login_method=1
  &user_account=%2C0%2C{ACCOUNT}
  &user_password={PASSWORD}
  &wlan_user_ip={CURRENT_IP}          # Dynamic IP from WAN interface
  &authex_enable={ISP_CHOICE}         # 1=China Unicom, 2=China Mobile
  ...
```

**Critical**: The `wlan_user_ip` parameter must match the current WAN IP, which is why dynamic detection is essential.

### Log Rotation Logic

When `LOG_TYPE=1` (file logging):
- Check file size before each write using `du -m`
- If size ≥ `LOG_SIZE_MB`, rename current log to `.old` suffix
- Only one `.old` backup is kept (overwrites previous)

## Common Development Commands

### Testing the Installer
```bash
# Run diagnostic tool first (recommended)
bash test.sh

# Run installer
bash install.sh

# Run uninstaller
bash uninstall.sh
```

### Service Management (Post-Installation)
```bash
# On the OpenWrt router
/etc/init.d/autologin start|stop|restart|status
/etc/init.d/autologin enable|disable  # Boot startup

# View logs (file mode)
tail -f /usr/local/autologin/logs/autologin.log

# View logs (syslog mode)
logread -f | grep autologin
```

### Manual Testing
```bash
# Test the generated runtime script directly
/usr/local/autologin/login.sh

# Check service status
ps | grep login.sh
```

## Configuration Reference

All configuration is stored in `/etc/config/autologin` after installation:

- `WAN_INTERFACE` - Network interface name (e.g., eth1, wan, pppoe-wan)
- `USER_ACCOUNT` - Login username
- `USER_PASSWORD` - Login password
- `ISP_CHOICE` - ISP selection (1=Unicom, 2=Mobile)
- `CHECK_INTERVAL` - Network check frequency in milliseconds
- `LOG_TYPE` - Logging mode (1=file, 2=syslog, 3=disabled)
- `LOG_FILE` - Log file path (when LOG_TYPE=1)
- `LOG_SIZE_MB` - Log rotation threshold in MB (when LOG_TYPE=1)

See `config.example` for detailed configuration options and examples.

## Critical Conventions

### File Paths
- **NEVER** modify the root `login.sh` for installations - it's legacy reference code
- The installer generates a NEW `login.sh` at `/usr/local/autologin/login.sh`
- Runtime script sources config from `/etc/config/autologin`

### Shell Script Standards
- All scripts use `#!/bin/sh` (not bash) for OpenWrt compatibility
- Use POSIX-compliant syntax (no bashisms)
- Use shell arithmetic `$((expr))` instead of external tools like `bc`
- Error handling uses `set -e` in installer
- Service script uses OpenWrt's `procd` framework (`USE_PROCD=1`)
- Always validate numeric inputs before passing to commands
- Use `safe_sleep` function instead of direct `sleep` calls in runtime scripts

### Security
- Config file has `chmod 600` (password protection)
- Passwords are never logged in responses
- No credentials in version control (use placeholders)

## Installation Flow

1. User uploads `install.sh` to OpenWrt router
2. Script detects system, installs dependencies if needed
3. Interactive prompts collect configuration
4. Script generates three files:
   - Runtime script at `/usr/local/autologin/login.sh`
   - Config file at `/etc/config/autologin`
   - Service wrapper at `/etc/init.d/autologin`
5. Service is enabled and started automatically
6. Runtime script begins monitoring loop

## Debugging Common Issues

### "Cannot get WAN IP"
- Check `WAN_INTERFACE` value in `/etc/config/autologin`
- Verify interface exists: `ip addr show` or `ifconfig`
- Check UCI network config: `uci show network.wan`

### "Service won't start"
- Check config file exists: `cat /etc/config/autologin`
- Test script manually: `/usr/local/autologin/login.sh`
- Check system log: `logread | tail -20`
- Verify script permissions: `ls -l /usr/local/autologin/login.sh`

### "Network keeps disconnecting"
- Review logs for authentication response errors
- Verify credentials in config file
- Check ISP_CHOICE matches actual ISP
- Test manual login via web interface to confirm credentials

## Important Code Patterns

### Config Loading Pattern
```bash
# All runtime scripts source config this way
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"  # Source config variables
else
    echo "Error: config not found"
    exit 1
fi
```

### Procd Service Pattern
```bash
# OpenWrt service template used in /etc/init.d/autologin
START=99  # Late boot start
STOP=15   # Early shutdown stop
USE_PROCD=1  # Use process management
```

### Heredoc Generation Pattern
Installer uses heredocs to generate files (search for `cat > "$FILE" << 'EOF'` patterns). The quotes around EOF prevent variable expansion during generation.
