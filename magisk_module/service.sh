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
