#!/bin/bash
# 检查 SUSFS 配置是否正确启用

echo "========================================"
echo "SUSFS 配置检查"
echo "========================================"

if [ -z "$KERNEL_ROOT" ]; then
    echo "错误: KERNEL_ROOT 未设置"
    exit 1
fi

DEFCONFIG="$KERNEL_ROOT/common/arch/arm64/configs/gki_defconfig"
KERNELSU_DIR="$KERNEL_ROOT/common/drivers/kernelsu"

echo ""
echo "1. 检查 defconfig 中的 SUSFS 配置："
if [ -f "$DEFCONFIG" ]; then
    grep "CONFIG_KSU_SUSFS" "$DEFCONFIG" || echo "  未找到 CONFIG_KSU_SUSFS"
else
    echo "  defconfig 文件不存在"
fi

echo ""
echo "2. 检查 KernelSU Kconfig 中的 SUSFS 配置："
if [ -f "$KERNELSU_DIR/Kconfig" ]; then
    grep -A5 "KSU_SUSFS" "$KERNELSU_DIR/Kconfig" | head -10
else
    echo "  KernelSU Kconfig 不存在"
fi

echo ""
echo "3. 检查 KernelSU Makefile/Kbuild："
if [ -f "$KERNELSU_DIR/Kbuild" ]; then
    echo "  使用 Kbuild:"
    grep -i "susfs" "$KERNELSU_DIR/Kbuild" || echo "  未找到 susfs 相关内容"
elif [ -f "$KERNELSU_DIR/Makefile" ]; then
    echo "  使用 Makefile:"
    grep -i "susfs" "$KERNELSU_DIR/Makefile" || echo "  未找到 susfs 相关内容"
else
    echo "  KernelSU Makefile/Kbuild 都不存在"
fi

echo ""
echo "4. 检查 SUSFS 文件是否存在："
SUSFS_FILES=(
    "$KERNEL_ROOT/common/fs/susfs.c"
    "$KERNEL_ROOT/common/include/linux/susfs.h"
    "$KERNEL_ROOT/common/include/linux/susfs_def.h"
)
for file in "${SUSFS_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $(basename $file) 存在"
    else
        echo "  ✗ $(basename $file) 不存在"
    fi
done

echo ""
echo "5. 检查 SUSFS 版本："
if [ -f "$KERNEL_ROOT/common/include/linux/susfs.h" ]; then
    grep "SUSFS_VERSION" "$KERNEL_ROOT/common/include/linux/susfs.h"
else
    echo "  susfs.h 不存在"
fi

echo ""
echo "========================================"
