#!/system/bin/sh
# ======================================================================
# TB522FU 模块共享日志组件 (v2.8+)
# 用法: 调用方先定义 MODDIR, 再  . "$MODDIR/logger.sh"
# 日志默认开启; WebUI 可通过 touch $MODDIR/.log_disabled 全局关闭
# 关键用途: 设备卡在开机 logo 时, post-fs-data 阶段的日志与 pstore
# 崩溃现场已落盘 /data, 恢复后可直接导出 module.log 定位根源
# ======================================================================

LOG_DIR="$MODDIR/logs"
LOG_FILE="$LOG_DIR/module.log"
LOG_MAX_BYTES=131072

__blog_rotate() {
    # 单文件超过 128KB 后轮转为 module.log.1, 防止无限膨胀
    [ -f "$LOG_FILE" ] || return 0
    __SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null)
    case "$__SIZE" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if [ "$__SIZE" -gt "$LOG_MAX_BYTES" ] 2>/dev/null; then
        mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
    return 0
}

# blog <TAG> <message>
blog() {
    [ -f "$MODDIR/.log_disabled" ] && return 0
    mkdir -p "$LOG_DIR" 2>/dev/null
    __blog_rotate
    echo "[$(date '+%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE" 2>/dev/null
}

# 会话分隔线, 便于区分每次开机/每次操作
blog_section() {
    blog "SESSION" "======================== $1 ========================"
}

# 转储上一次启动的崩溃现场 (pstore ramoops / last_kmsg)。
# 仅保留与显示/亮度/system_server 崩溃相关的关键字行, 控制体积。
blog_dump_crash() {
    [ -f "$MODDIR/.log_disabled" ] && return 0
    mkdir -p "$LOG_DIR" 2>/dev/null
    blog "CRASH-DUMP" "开始转储上一次启动的内核/系统崩溃现场..."
    __DUMP_OK=0
    for __f in /sys/fs/pstore/console-ramoops* /sys/fs/pstore/dmesg-ramoops* /proc/last_kmsg; do
        if [ -f "$__f" ]; then
            __DUMP_OK=1
            blog "CRASH-DUMP" "来源: $__f"
            grep -aE "DisplayDeviceConfig|display_id|brightness|Brightness|OplusDisplaySpline|system_server|systemServer|Fatal|FATAL|\bDEBUG\b|Exception|panic|Watchdog|watchdog|died|reboot" "$__f" 2>/dev/null | tail -n 150 >> "$LOG_FILE" 2>/dev/null
        fi
    done
    if [ "$__DUMP_OK" = "0" ]; then
        blog "CRASH-DUMP" "未找到可用的 pstore / last_kmsg 记录 (可能内核未开启 ramoops 或已被清空)"
    else
        blog "CRASH-DUMP" "崩溃现场转储完成, 请将整个 module.log 提供给开发者"
    fi
}

blog_sync() {
    sync 2>/dev/null
}
