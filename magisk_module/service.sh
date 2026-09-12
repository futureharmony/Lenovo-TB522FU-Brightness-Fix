#!/system/bin/sh
MODDIR=${0%/*}

# 监控系统完整进入桌面
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# 延迟 15 秒等待 DisplayPowerController 与 SystemServer 平稳运行
sleep 15

# ==================== 开机看门狗解除警报 ====================
# 系统已成功平稳运行，证明本次开机完全安全，清零崩溃计数器并清除开机标记
rm -f "$MODDIR/.booting"
rm -f "$MODDIR/.boot_crash_count"

# 关闭低电量节电模式干扰
settings put global low_power 0 2>/dev/null

# 全局 LCD HDR / Ultra HDR 智能屏蔽策略 (适配用户偏好)
if [ ! -f "$MODDIR/.hdr_unblocked" ]; then
    # 默认或用户选择开启屏蔽: 保护 LCD 全局背光
    cmd display set-user-disabled-hdr-types 1 2 3 4 2>/dev/null
    settings put global user_disabled_hdr_formats "1,2,3,4" 2>/dev/null
    setprop persist.sys.feature.uhdr.support false 2>/dev/null
    touch "$MODDIR/.hdr_blocked"
else
    # 用户在 WebUI 中显式选择了恢复 HDR
    cmd display set-user-disabled-hdr-types "" 2>/dev/null
    settings put global user_disabled_hdr_formats "" 2>/dev/null
    setprop persist.sys.feature.uhdr.support true 2>/dev/null
fi

# ==================== 用户自定义曲线开机自愈对齐 ====================
if [ -f "$MODDIR/custom_points.json" ]; then
    sh "$MODDIR/apply_curve.sh" json "$MODDIR/custom_points.json" >/dev/null 2>&1
fi
