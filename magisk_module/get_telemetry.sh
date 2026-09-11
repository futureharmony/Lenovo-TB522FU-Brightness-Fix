#!/system/bin/sh
# TB522FU 实时遥测数据采集脚本
# 输出格式: LUX|HW_BACKLIGHT|SYS_BRIGHTNESS

LUX=$(dumpsys display 2>/dev/null | grep -m 1 "mFinalLux = " | awk '{print $3}')
if [ -z "$LUX" ]; then
    LUX=$(dumpsys sensorservice 2>/dev/null | awk '/Ambient Light Sensor/ {f=1; next} /last [0-9]+ events/ && f {f=0} f && /wall=/ {last=$0} END {print last}' | sed -E 's/.*wall=[^)]+\)[ ]*([0-9.]+).*/\1/')
fi

HW=$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null)

BRT=$(dumpsys display 2>/dev/null | grep -m 1 "mCachedBrightnessInfo.brightness=" | awk -F'=' '{print $2}')
if [ -z "$BRT" ]; then
    BRT=$(settings get system screen_brightness 2>/dev/null)
fi

echo "${LUX:-0.0}|${HW:-0}|${BRT:-222}"
