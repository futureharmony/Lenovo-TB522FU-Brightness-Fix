#!/system/bin/sh
# TB522FU LCD HDR / Ultra HDR 智能屏蔽控制脚本
# 支持在 WebUI 中免重启热切换

MODDIR=${0%/*}
ACTION="${1:-status}"

case "$ACTION" in
    "status")
        # 检测当前系统真实禁用状态
        DISABLED_TYPES=$(cmd display get-user-disabled-hdr-types 2>/dev/null)
        UHDR_PROP=$(getprop persist.sys.feature.uhdr.support)
        
        # 判断是否处于屏蔽状态
        if echo "$DISABLED_TYPES" | grep -qE "1.*2.*3.*4|1" || [ "$UHDR_PROP" = "false" ] || [ -f "$MODDIR/.hdr_blocked" ]; then
            echo '{"blocked":true,"types":"1,2,3,4","uhdr":false}'
        else
            echo '{"blocked":false,"types":"","uhdr":true}'
        fi
        ;;

    "enable"|"on"|"block")
        # 1. 系统显示服务禁用所有 HDR 格式 (1=HDR10, 2=HLG, 3=HDR10+, 4=Dolby Vision)
        cmd display set-user-disabled-hdr-types 1 2 3 4 2>/dev/null
        settings put global user_disabled_hdr_formats "1,2,3,4" 2>/dev/null

        # 2. 运行时属性设置
        setprop persist.sys.feature.uhdr.support false 2>/dev/null
        setprop persist.sys.feature.hdr_vision_app 0 2>/dev/null
        setprop persist.sys.feature.localhdr_version 0 2>/dev/null

        # 3. 记录持久化状态 (默认开启屏蔽)
        touch "$MODDIR/.hdr_blocked"
        rm -f "$MODDIR/.hdr_unblocked"

        echo '{"success":true,"blocked":true,"message":"已开启系统级 HDR 屏蔽，LCD 全局背光压暗已消除"}'
        ;;

    "disable"|"off"|"unblock")
        # 1. 恢复系统 HDR 格式支持
        cmd display set-user-disabled-hdr-types "" 2>/dev/null
        settings put global user_disabled_hdr_formats "" 2>/dev/null

        # 2. 恢复运行时属性
        setprop persist.sys.feature.uhdr.support true 2>/dev/null
        setprop persist.sys.feature.hdr_vision_app 1 2>/dev/null
        setprop persist.sys.feature.localhdr_version 1 2>/dev/null

        # 3. 记录持久化状态
        touch "$MODDIR/.hdr_unblocked"
        rm -f "$MODDIR/.hdr_blocked"

        echo '{"success":true,"blocked":false,"message":"已恢复系统原生 HDR 支持"}'
        ;;

    *)
        echo "Usage: $0 {status|enable|disable}"
        exit 1
        ;;
esac
