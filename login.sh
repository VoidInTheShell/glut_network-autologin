#!/bin/sh
 
# 获取eth1接口的IP地址（这里需要改成你自己的接口 可以在路由器的网络-接口-设备中查看）
CURRENT_IP=$(ifconfig wan | grep 'inet addr:' | awk '{print $2}' | cut -d: -f2)
# 获取eth1接口的MAC地址（这里需要改成你自己的接口 可以在路由器的网络-接口-设备中查看）
MAC_ADDRESS=$(ifconfig wan | grep 'HWaddr' | awk '{print $5}' | tr '[:upper:]' '[:lower:]' | tr ':' '-')
# 打印调试信息
echo "Current IP: $CURRENT_IP"
echo "MAC Address: $MAC_ADDRESS"
#账号密码
USER_ACCOUNT="xxxxxxxx"
output_file="log.txt"
USER_PASSWORD="xxxxx"
#运营商选择，1为联通2为移动
AUTHEX_ENABLE="1"

url="http://10.10.11.11:801/eportal/portal/login?callback=dr1003&login_method=1&user_account=%2C0%2C$USER_ACCOUNT&user_password=$USER_PASSWORD&wlan_user_ip=$CURRENT_IP&wlan_user_ipv6=&wlan_user_mac=000000000000&wlan_ac_ip=&wlan_ac_name=&page_index=pMnaGv1756888844&authex_enable=$AUTHEX_ENABLE&jsVersion=4.2.1&terminal_type=1&lang=zh-cn&lang=zh"
echo $url
check_and_reconnect() {
    (echo "$(date +'%Y-%m-%d %H:%M:%S')"; wget -qO- $url; echo) >> $output_file
}

ping -c 1 119.29.29.29 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Internet OK"
else
    check_and_reconnect
    sleep 10
    ping -c 1 119.29.29.29 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "连接已恢复"
    else
        check_and_reconnect
    fi
fi
 
