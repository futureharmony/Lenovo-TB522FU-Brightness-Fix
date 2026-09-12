#!/sbin/sh
##########################################################################################
# TB522FU ColorOS 16 自动亮度优化模块 - 安装前环境与机制校验探针
##########################################################################################

ui_print "***************************************************"
ui_print "  联想拯救者 Y900 (TB522FU) 自动亮度优化模块安装程序  "
ui_print "  作者: futureharmony                              "
ui_print "***************************************************"

ui_print "- 正在进行前置环境与 ColorOS 调光机制嗅探..."

# 1. 硬件面板配置动态嗅探与自适应
PANEL_CFG=""
for cfg in /vendor/etc/displayconfig/display_id_*.xml; do
    if [ -f "$cfg" ]; then
        PANEL_CFG="$cfg"
        break
    fi
done

if [ -z "$PANEL_CFG" ]; then
    ui_print "❌ [错误] 未在 /vendor/etc/displayconfig/ 中检测到任何屏幕面板配置！"
    ui_print "👉 本模块需要设备具备标准的 DisplayDeviceConfig 屏幕配置文件。"
    ui_print "👉 为防止屏幕背光与调光异常，已安全中止刷入！"
    abort "未检测到屏幕配置文件，终止安装。"
fi
ui_print "  [✓] 硬件面板校验通过: 检测到真实屏幕配置 $(basename "$PANEL_CFG")"

# 2. 系统版本与架构指纹校验 (确认是 ColorOS / Oplus 架构)
IS_OPLUS=false
if [ -n "$(getprop ro.build.version.oplusrom)" ] || \
   [ -n "$(getprop ro.oplus.version.my_manifest)" ] || \
   [ -d "/my_product" ] || \
   [ -f "/system/framework/oplus-services.jar" ] || \
   [ -f "/system_ext/framework/oplus-services.jar" ]; then
    IS_OPLUS=true
fi

if [ "$IS_OPLUS" != "true" ]; then
    ui_print "❌ [错误] 当前系统未检测到 ColorOS / Oplus 架构环境！"
    ui_print "👉 本模块仅适用于移植了 ColorOS 16 的 TB522FU 设备。"
    abort "非 ColorOS 系统，终止安装。"
fi
ui_print "  [✓] 系统架构校验通过: 检测到 ColorOS / Oplus 运行环境"

# 3. 核心服务字节码深度嗅探 (Dex Inspection 探针)
# 快速反查 classes.dex 中是否存在 OplusDisplaySplineManager 与 10240 样条机制
OPLUS_SERVICES=""
for candidate in \
    /system/framework/oplus-services.jar \
    /system_ext/framework/oplus-services.jar \
    /system/system_ext/framework/oplus-services.jar \
    /my_product/framework/oplus-services.jar; do
    if [ -f "$candidate" ]; then
        OPLUS_SERVICES="$candidate"
        break
    fi
done

if [ -n "$OPLUS_SERVICES" ]; then
    ui_print "- 正在对 $(basename "$OPLUS_SERVICES") 执行字节码机制探针扫描..."
    if unzip -p "$OPLUS_SERVICES" classes*.dex 2>/dev/null | grep -Fq "OplusDisplaySplineManager"; then
        ui_print "  [✓] 字节码机制嗅探成功: 确认存在 OplusDisplaySplineManager 样条引擎"
    else
        ui_print "⚠️ [警告] 未在 $(basename "$OPLUS_SERVICES") 中扫描到 OplusDisplaySplineManager！"
        ui_print "👉 当前 ROM 的显示服务可能与标准 ColorOS 16 存在结构差异。"
        ui_print "👉 为防止系统崩溃或卡标，已安全中止刷入！"
        abort "未检测到预定调光机制，终止安装。"
    fi
else
    ui_print "❌ [错误] 未在系统中检测到 oplus-services.jar 核心服务包！"
    abort "缺少核心系统框架，终止安装。"
fi

# 4. 目标挂载点完整性校验
DEF_XML="/system_ext/etc/display_brightness_config_default.xml"
COMMON_XML="/system/etc/display_brightness_config_common.xml"
if [ ! -f "$DEF_XML" ] || [ ! -f "$COMMON_XML" ]; then
    ui_print "❌ [错误] 系统原厂亮度配置文件缺失，无法执行联动挂载！"
    abort "系统配置文件不完整，终止安装。"
fi
ui_print "  [✓] 目标挂载点完整性校验通过"

# 5. 自动同步真实面板配置文件名 (解除跨批次/跨设备 ID 限制)
REAL_PANEL_NAME=$(basename "$PANEL_CFG")
if [ -n "$REAL_PANEL_NAME" ] && [ "$REAL_PANEL_NAME" != "display_id_4630947077023927187.xml" ]; then
    cp -f "$MODPATH/vendor/etc/displayconfig/display_id_4630947077023927187.xml" "$MODPATH/vendor/etc/displayconfig/$REAL_PANEL_NAME"
    ui_print "  [✓] 已自动生成适配当前设备的屏幕配置: $REAL_PANEL_NAME"
fi

# 6. 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/apply_curve.sh" 0 0 0755
set_perm "$MODPATH/get_telemetry.sh" 0 0 0755
set_perm "$MODPATH/hdr_control.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

ui_print "✅ 所有前置环境校验全部通过，模块已成功部署！"
