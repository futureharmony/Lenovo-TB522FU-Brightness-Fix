#!/system/bin/sh
MODDIR=${0%/*}

. "$MODDIR/logger.sh" 2>/dev/null

blog_section "service.sh late_start 会话开始"
blog "SERVICE" "等待 sys.boot_completed ..."

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
blog "WATCHDOG" "系统已平稳进入桌面, 本次开机安全: 清除 .booting 与崩溃计数器"

# 记录关键挂载目标的实时校验和, 用于确认 bind mount 是否真实生效
blog "VERIFY" "挂载目标校验和: $(md5sum /system/etc/display_brightness_config_common.xml /system_ext/etc/display_brightness_config_default.xml /vendor/etc/displayconfig/display_id_*.xml 2>/dev/null | tr '\n' ' ')"

# 采集本启动周期内显示子系统日志 (确认挂载的配置被系统正常解析)
LOGCAT_SNIP=$(logcat -d 2>/dev/null | grep -aiE "DisplayDeviceConfig|brightness_config|OplusDisplaySpline|BrightnessSpline" | tail -n 60)
if [ -n "$LOGCAT_SNIP" ]; then
    blog "LOGCAT" "显示子系统相关日志 (本次启动, 截取最后 60 行):"
    echo "$LOGCAT_SNIP" | while IFS= read -r line; do
        blog "LOGCAT" "$line"
    done
else
    blog "LOGCAT" "本启动周期未捕获到显示子系统相关日志"
fi

# 关闭低电量节电模式干扰
settings put global low_power 0 2>/dev/null

# 全局 LCD HDR / Ultra HDR 智能屏蔽策略 (适配用户偏好)
if [ ! -f "$MODDIR/.hdr_unblocked" ]; then
    # 默认或用户选择开启屏蔽: 保护 LCD 全局背光
    cmd display set-user-disabled-hdr-types 1 2 3 4 2>/dev/null
    settings put global user_disabled_hdr_formats "1,2,3,4" 2>/dev/null
    setprop persist.sys.feature.uhdr.support false 2>/dev/null
    touch "$MODDIR/.hdr_blocked"
    blog "HDR" "执行默认策略: 屏蔽 HDR 类型 1,2,3,4 + 关闭 UHDR"
else
    # 用户在 WebUI 中显式选择了恢复 HDR
    cmd display set-user-disabled-hdr-types "" 2>/dev/null
    settings put global user_disabled_hdr_formats "" 2>/dev/null
    setprop persist.sys.feature.uhdr.support true 2>/dev/null
    blog "HDR" "执行用户策略: 恢复系统原生 HDR 支持"
fi

# ==================== 用户自定义曲线开机自愈对齐 ====================
if [ -f "$MODDIR/custom_points.json" ]; then
    blog "SELF-HEAL" "检测到 custom_points.json, 开始执行开机曲线对齐..."
    APPLY_OUT=$(sh "$MODDIR/apply_curve.sh" json "$MODDIR/custom_points.json" 2>&1)
    APPLY_RC=$?
    blog "SELF-HEAL" "开机曲线对齐完成 (退出码 $APPLY_RC): $(echo "$APPLY_OUT" | tail -n 1)"
else
    blog "SELF-HEAL" "未检测到 custom_points.json, 跳过曲线对齐"
fi

blog_sync
blog "SERVICE" "service.sh 后置任务全部完成"
