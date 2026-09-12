#!/system/bin/sh
MODDIR="${0%/*}"

# ==================== 开机看门狗自愈机制 (Bootloop Watchdog & Auto-Fallback) ====================
BOOT_FLAG="$MODDIR/.booting"
CRASH_CNT="$MODDIR/.boot_crash_count"
MAX_CRASHES=2

if [ -f "$MODDIR/disable" ]; then
    exit 0
fi

if [ -f "$BOOT_FLAG" ]; then
    # 上次启动标记未被 service.sh 清除，说明系统尚未稳定进入桌面就发生了重启或崩溃
    COUNT=$(cat "$CRASH_CNT" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$CRASH_CNT"

    if [ "$COUNT" -ge "$MAX_CRASHES" ]; then
        # 达到连续崩溃阈值，触发紧急熔断保护：就地禁用本模块，完全跳过挂载，确保设备顺利开机！
        touch "$MODDIR/disable"
        rm -f "$BOOT_FLAG"
        echo "[$(date)] Watchdog tripped: auto-disabled module after $COUNT boot anomalies to prevent bootloop." > "$MODDIR/watchdog_fallback.log"
        exit 0
    fi
else
    # 写入本次开机监测标记
    touch "$BOOT_FLAG"
fi

# ==================== SELinux 标签规整 (杜绝 webview_zygote FD 泄露崩溃) ====================
chcon -R u:object_r:system_file:s0 "$MODDIR/system" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/system_ext" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/my_product" 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 "$MODDIR/vendor" 2>/dev/null
chcon u:object_r:system_file:s0 "$MODDIR"/*.sh 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/webroot" 2>/dev/null

# ==================== 核心配置多级联动挂载 ====================
# 1. 主亮度映射表 (10240 阶线性标尺)
TARGET_DEF="/system_ext/etc/display_brightness_config_default.xml"
SRC_DEF="$MODDIR/system_ext/etc/display_brightness_config_default.xml"
if [ -f "$SRC_DEF" ] && [ -f "$TARGET_DEF" ]; then
    mount -o bind "$SRC_DEF" "$TARGET_DEF"
fi

# 2. 环境光 Lux 到 Nit 黄金曲线
TARGET_COMMON="/system/etc/display_brightness_config_common.xml"
SRC_COMMON="$MODDIR/system/etc/display_brightness_config_common.xml"
if [ -f "$SRC_COMMON" ] && [ -f "$TARGET_COMMON" ]; then
    mount -o bind "$SRC_COMMON" "$TARGET_COMMON"
fi

TARGET_EXT_COMMON="/system_ext/etc/display_brightness_config_common.xml"
if [ -f "$SRC_COMMON" ] && [ -e "$TARGET_EXT_COMMON" ]; then
    mount -o bind "$SRC_COMMON" "$TARGET_EXT_COMMON"
fi

# 3. P_D 次级设备配置
TARGET_PD="/my_product/vendor/etc/display_brightness_config_P_D.xml"
SRC_PD="$MODDIR/my_product/vendor/etc/display_brightness_config_P_D.xml"
if [ -f "$SRC_PD" ] && [ -f "$TARGET_PD" ]; then
    mount -o bind "$SRC_PD" "$TARGET_PD"
fi

# 4. 屏幕面板硬件配置文件 (动态遍历挂载系统中所有的 display_id_*.xml，彻底解除特定 ID 硬编码限制)
SRC_DISP="$MODDIR/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
if [ -f "$SRC_DISP" ]; then
    for target_disp in /vendor/etc/displayconfig/display_id_*.xml; do
        if [ -f "$target_disp" ]; then
            mount -o bind "$SRC_DISP" "$target_disp"
        fi
    done
fi
