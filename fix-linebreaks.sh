#!/bin/sh
#
# 修复 Windows 换行符问题
# 将 CRLF 转换为 LF
#

echo "正在修复换行符问题..."

# 修复所有 .sh 文件
for file in *.sh; do
    if [ -f "$file" ]; then
        echo "处理: $file"
        # 使用 sed 删除 \r
        sed -i 's/\r$//' "$file" 2>/dev/null || sed -i '' 's/\r$//' "$file"
        chmod +x "$file"
    fi
done

echo "修复完成！"
echo ""
echo "现在可以运行："
echo "  ./install.sh"
