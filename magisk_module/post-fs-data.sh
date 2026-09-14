#!/system/bin/sh
MODDIR="${0%/*}"

. "$MODDIR/logger.sh" 2>/dev/null

# ==================== 开机看门狗自愈机制 (Bootloop Watchdog & Auto-Fallback) ====================
BOOT_FLAG="$MODDIR/.booting"
CRASH_CNT="$MODDIR/.boot_crash_count"
MAX_CRASHES=2

if [ -f "$MODDIR/disable" ]; then
    exit 0
fi

# 会话头 (越早落盘越好): 即使本次开机卡死在 logo, 也能证明模块执行到了哪一步
blog_section "post-fs-data 开机挂载会话开始"
blog "BOOT" "型号: $(getprop ro.product.model) | ROM: $(getprop ro.build.version.oplusrom) | 指纹: $(getprop ro.build.fingerprint)"
blog_sync

if [ -f "$BOOT_FLAG" ]; then
    # 上次启动标记未被 service.sh 清除，说明系统尚未稳定进入桌面就发生了重启或崩溃
    COUNT=$(cat "$CRASH_CNT" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$CRASH_CNT"

    if [ "$COUNT" -ge "$MAX_CRASHES" ]; then
        # 达到连续崩溃阈值，触发紧急熔断保护：就地禁用本模块，完全跳过挂载，确保设备顺利开机！
        touch "$MODDIR/disable"
        rm -f "$BOOT_FLAG"
        blog "WATCHDOG" "!!! 连续 $COUNT 次开机异常, 紧急熔断: 已自动禁用本模块 (watchdog_fallback.log 同步记录) !!!"
        echo "[$(date '+%m-%d %H:%M:%S')] Watchdog tripped: auto-disabled module after $COUNT boot anomalies to prevent bootloop." > "$MODDIR/watchdog_fallback.log"
        blog_dump_crash
        blog_sync
        exit 0
    fi

    blog "WATCHDOG" "检测到上一次启动未完成 (连续异常第 $COUNT 次), 正在转储崩溃现场..."
    blog_dump_crash
    blog_sync
else
    # 写入本次开机监测标记
    touch "$BOOT_FLAG"
    blog "WATCHDOG" "写入本次开机监测标记 (.booting), 由 service.sh 在进入桌面后清除"
fi

# ==================== SELinux 标签规整 (杜绝 webview_zygote FD 泄露崩溃) ====================
chcon -R u:object_r:system_file:s0 "$MODDIR/system" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/system_ext" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/my_product" 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 "$MODDIR/vendor" 2>/dev/null
chcon u:object_r:system_file:s0 "$MODDIR"/*.sh 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/webroot" 2>/dev/null
blog "SELINUX" "模块文件标签规整完成"

# ==================== 挂载与 schema 嗅探工具 ====================
# do_bind_mount <描述> <src> <dst>
do_bind_mount() {
    if [ ! -f "$2" ] || [ ! -f "$3" ]; then
        blog "MOUNT" "跳过: $1 (src=$2 存在:$([ -f "$2" ] && echo 1 || echo 0) / dst=$3 存在:$([ -f "$3" ] && echo 1 || echo 0))"
        return 1
    fi
    if mount -o bind "$2" "$3" 2>/dev/null; then
        blog "MOUNT" "成功: $1 ($3 <= $(wc -c < "$2") 字节)"
        return 0
    fi
    blog "MOUNT" "失败: $1 (mount -o bind $2 -> $3)"
    return 1
}

# check_schema_pair <描述> <src> <dst> <必需标记>
# 双向校验模块文件与设备目标文件都包含必需结构标记, 任一缺失即跳过挂载,
# 防止跨批次/跨固件的配置结构差异导致 system_server / vendor 显示服务崩溃卡标
check_schema_pair() {
    if [ ! -f "$2" ]; then
        blog "SCHEMA" "跳过: $1 模块侧文件不存在 ($2)"
        return 1
    fi
    if [ ! -f "$3" ]; then
        blog "SCHEMA" "跳过: $1 设备侧目标不存在 ($3)"
        return 1
    fi
    if ! grep -q "$4" "$3" 2>/dev/null; then
        blog "SCHEMA" "警告: 设备目标 $3 缺少结构标记 [$4], 疑似固件结构差异, 本次跳过挂载以防卡标"
        return 1
    fi
    if ! grep -q "$4" "$2" 2>/dev/null; then
        blog "SCHEMA" "警告: 模块文件 $2 缺少结构标记 [$4] (可能未经安装器以设备原版重建), 本次跳过挂载"
        return 1
    fi
    return 0
}

# ==================== 核心配置多级联动挂载 ====================

# 1. 主亮度映射表 (10240 阶线性标尺) — 额外校验 max/min 级别数一致
TARGET_DEF="/system_ext/etc/display_brightness_config_default.xml"
SRC_DEF="$MODDIR/system_ext/etc/display_brightness_config_default.xml"
if check_schema_pair "主亮度映射表" "$SRC_DEF" "$TARGET_DEF" "<brightness_table"; then
    DEF_MAX_SRC=$(sed -n 's/.*max="\([0-9]*\)".*/\1/p' "$SRC_DEF" | head -n 1)
    DEF_MAX_DST=$(sed -n 's/.*max="\([0-9]*\)".*/\1/p' "$TARGET_DEF" | head -n 1)
    blog "SCHEMA" "主亮度映射表级别数对比: 模块侧 max=$DEF_MAX_SRC / 设备侧 max=$DEF_MAX_DST"
    if [ -n "$DEF_MAX_SRC" ] && [ -n "$DEF_MAX_DST" ] && [ "$DEF_MAX_SRC" != "$DEF_MAX_DST" ]; then
        blog "SCHEMA" "警告: 双方亮度表级别数不一致, 强行挂载会导致调光引擎异常, 本次跳过挂载!"
    else
        do_bind_mount "主亮度映射表 (default.xml)" "$SRC_DEF" "$TARGET_DEF"
    fi
fi

# 2. 环境光 Lux 到 Nit 黄金曲线
TARGET_COMMON="/system/etc/display_brightness_config_common.xml"
SRC_COMMON="$MODDIR/system/etc/display_brightness_config_common.xml"
if check_schema_pair "Lux-Nit 曲线 (system common)" "$SRC_COMMON" "$TARGET_COMMON" "<lux_table"; then
    do_bind_mount "Lux-Nit 曲线 (system common.xml)" "$SRC_COMMON" "$TARGET_COMMON"
fi

TARGET_EXT_COMMON="/system_ext/etc/display_brightness_config_common.xml"
if check_schema_pair "Lux-Nit 曲线 (system_ext common)" "$SRC_COMMON" "$TARGET_EXT_COMMON" "<lux_table"; then
    do_bind_mount "Lux-Nit 曲线 (system_ext common.xml)" "$SRC_COMMON" "$TARGET_EXT_COMMON"
fi

# 3. P_D 次级设备配置
TARGET_PD="/my_product/vendor/etc/display_brightness_config_P_D.xml"
SRC_PD="$MODDIR/my_product/vendor/etc/display_brightness_config_P_D.xml"
if check_schema_pair "P_D 次级配置" "$SRC_PD" "$TARGET_PD" "<brightness_table"; then
    do_bind_mount "P_D 次级配置 (P_D.xml)" "$SRC_PD" "$TARGET_PD"
fi

# 4. 屏幕面板硬件配置文件 — 仅精确挂载 TB522FU 真实主屏物理配置 (.panel_name 智能纠偏)
#    严禁挂载 DP 副屏/外接投屏配置文件 (如 display_id_4630947039571902850.xml)，
#    否则会导致 vendor 显示服务在开机早期因参数不匹配崩溃卡 Logo 软重启！
detect_primary_panel() {
    # 4.1 首选 TB522FU 原厂已知物理主屏配置文件
    local known_primary="/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
    if [ -f "$known_primary" ]; then
        echo "$known_primary"
        return 0
    fi

    # 4.2 若存在 .panel_name，校验其是否真实为主屏 (若原记录为已知副屏 ID 则丢弃纠偏)
    if [ -f "$MODDIR/.panel_name" ]; then
        local saved_name=$(cat "$MODDIR/.panel_name" 2>/dev/null | tr -d '\r\n ')
        if [ -n "$saved_name" ] && [ -f "/vendor/etc/displayconfig/$saved_name" ]; then
            if grep -q "<highBrightnessMode" "/vendor/etc/displayconfig/$saved_name" 2>/dev/null; then
                echo "/vendor/etc/displayconfig/$saved_name"
                return 0
            fi
        fi
    fi

    # 4.3 特征嗅探: 真实内部 OLED 主屏必含 highBrightnessMode 与 sdrHdrRatioMap
    local cand=""
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q "<highBrightnessMode" "$cand" 2>/dev/null && grep -q "<sdrHdrRatioMap" "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done

    # 4.4 linear 映射
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q '<screenBrightnessMap interpolation="linear">' "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done

    # 4.5 体积最大者兜底 (主屏配置包含完整调光样条与 ramp 参数，远大于 ~1KB 的副屏配置)
    local best_cfg=""
    local max_size=0
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        local sz=$(wc -c < "$cand" 2>/dev/null || echo 0)
        case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
        if [ "$sz" -gt "$max_size" ]; then
            max_size="$sz"
            best_cfg="$cand"
        fi
    done
    if [ -n "$best_cfg" ]; then
        echo "$best_cfg"
        return 0
    fi

    return 1
}

PANEL_CFG=$(detect_primary_panel)
if [ -n "$PANEL_CFG" ] && [ -f "$PANEL_CFG" ]; then
    PANEL_NAME=$(basename "$PANEL_CFG")
    echo "$PANEL_NAME" > "$MODDIR/.panel_name" 2>/dev/null

    PANEL_COUNT=0
    PANEL_LIST=""
    for f in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$f" ] || continue
        PANEL_COUNT=$((PANEL_COUNT + 1))
        PANEL_LIST="$PANEL_LIST $(basename "$f")"
    done
    blog "PANEL" "设备面板配置探测: 共 $PANEL_COUNT 个 ->$PANEL_LIST (智能锁定主屏目标: $PANEL_NAME)"

    # 防御清理: 移除非主屏的模块残留文件，杜绝 Magisk Magic Mount 误将副屏覆盖
    for f in "$MODDIR/vendor/etc/displayconfig/"*.xml; do
        [ -f "$f" ] || continue
        if [ "$(basename "$f")" != "$PANEL_NAME" ]; then
            rm -f "$f"
            blog "PANEL" "已清理模块内残留的非主屏配置: $(basename "$f")"
        fi
    done

    TARGET_DISP="$PANEL_CFG"
    SRC_DISP="$MODDIR/vendor/etc/displayconfig/$PANEL_NAME"
    if [ ! -f "$SRC_DISP" ]; then
        SRC_DISP="$MODDIR/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
    fi
    if check_schema_pair "面板配置 ($PANEL_NAME)" "$SRC_DISP" "$TARGET_DISP" "screenBrightnessMap"; then
        do_bind_mount "面板配置 ($PANEL_NAME)" "$SRC_DISP" "$TARGET_DISP"
    fi
else
    blog "PANEL" "警告: 未找到任何有效的主屏幕 display_id_*.xml, 跳过面板配置挂载"
fi

blog_sync
blog "BOOT" "post-fs-data 会话结束, 移交 late_start (service.sh)"
