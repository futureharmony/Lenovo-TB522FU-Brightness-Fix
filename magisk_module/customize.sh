#!/sbin/sh
##########################################################################################
# TB522FU ColorOS 16 自动亮度优化模块 - 安装前环境与机制校验探针
##########################################################################################

ui_print "***************************************************"
ui_print "  联想拯救者 Y900 (TB522FU) 自动亮度优化模块安装程序  "
ui_print "  作者: futureharmony                              "
ui_print "***************************************************"

# 统一安装日志: 同时输出到安装器界面与模块诊断日志 (logs/module.log)
MP="$MODPATH"
OLD_DIR="/data/adb/modules/tb522fu_brightness_fix"
mkdir -p "$MP/logs" 2>/dev/null
_ilog() {
    ui_print "$1"
    echo "[$(date '+%m-%d %H:%M:%S')] [INSTALL] $1" >> "$MP/logs/module.log" 2>/dev/null
}

_ilog "======================== 安装会话开始 (customize.sh) ========================"
_ilog "设备: $(getprop ro.product.model) | ROM: $(getprop ro.build.version.oplusrom) | 指纹: $(getprop ro.build.fingerprint)"
WV_INSTALL_INFO=$(dumpsys webviewupdate 2>/dev/null | head -n 6 | tr '\n' ' ')
_ilog "WebView 供应商: ${WV_INSTALL_INFO:-未获取到 (可能缺少 WebView Provider, WebUI 将无法打开)}"

ui_print "- 正在进行前置环境与 ColorOS 调光机制嗅探..."

# 1. 硬件面板配置动态嗅探与自适应 (智能选定 TB522FU 主屏幕物理面板)
# TB522FU 原厂 OLED 物理主屏配置为 display_id_4630947077023927187.xml
# 必须杜绝按字母排序盲目取首个文件导致误选中 DP 副屏/外部投屏配置 (如 display_id_4630947039571902850.xml) 引发开机卡 Logo！
detect_primary_panel() {
    # 1.1 首选已知主屏: TB522FU 原厂 OLED 物理主屏
    local known_primary="/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
    if [ -f "$known_primary" ]; then
        echo "$known_primary"
        return 0
    fi

    # 1.2 运行期 dumpsys 探测 (若在已开机系统内刷入)
    if command -v dumpsys >/dev/null 2>&1; then
        local sys_id=$(dumpsys display 2>/dev/null | grep -oE 'display_id_[0-9]+\.xml' | head -n 1)
        if [ -n "$sys_id" ] && [ -f "/vendor/etc/displayconfig/$sys_id" ]; then
            echo "/vendor/etc/displayconfig/$sys_id"
            return 0
        fi
    fi

    # 1.3 特征嗅探: 真实内部 OLED 主屏必含 highBrightnessMode 与 sdrHdrRatioMap (DP/虚拟副屏不含)
    local cand=""
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q "<highBrightnessMode" "$cand" 2>/dev/null && grep -q "<sdrHdrRatioMap" "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done

    # 1.4 特征嗅探 2: 含有 linear screenBrightnessMap
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q '<screenBrightnessMap interpolation="linear">' "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done

    # 1.5 体积最大者兜底 (主屏配置包含完整调光样条与 ramp 参数，远大于 ~1KB 的副屏配置)
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

if [ -z "$PANEL_CFG" ] || [ ! -f "$PANEL_CFG" ]; then
    ui_print "❌ [错误] 未在 /vendor/etc/displayconfig/ 中检测到任何屏幕面板配置！"
    ui_print "👉 本模块需要设备具备标准的 DisplayDeviceConfig 屏幕配置文件。"
    ui_print "👉 为防止屏幕背光与调光异常，已安全中止刷入！"
    abort "未检测到屏幕配置文件，终止安装。"
fi
_ilog "  [✓] 硬件面板校验通过: 锁定主屏配置 $(basename "$PANEL_CFG")"

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
_ilog "  [✓] 系统架构校验通过: 检测到 ColorOS / Oplus 运行环境"

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
        _ilog "  [✓] 字节码机制嗅探成功: 确认存在 OplusDisplaySplineManager 样条引擎"
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
PD_XML="/my_product/vendor/etc/display_brightness_config_P_D.xml"
if [ ! -f "$DEF_XML" ] || [ ! -f "$COMMON_XML" ]; then
    ui_print "❌ [错误] 系统原厂亮度配置文件缺失，无法执行联动挂载！"
    abort "系统配置文件不完整，终止安装。"
fi
_ilog "  [✓] 目标挂载点完整性校验通过"

# ============ 5. 保留用户历史状态与诊断日志 (跨升级延续) ============
if [ "$MP" != "$OLD_DIR" ] && [ -d "$OLD_DIR" ]; then
    cp -f "$OLD_DIR/custom_points.json" "$MP/" 2>/dev/null
    cp -f "$OLD_DIR/.hdr_blocked" "$OLD_DIR/.hdr_unblocked" "$MP/" 2>/dev/null
    cp -f "$OLD_DIR/.log_disabled" "$MP/" 2>/dev/null
    cp -f "$OLD_DIR/logs/module.log" "$MP/logs/module.log" 2>/dev/null
    cp -f "$OLD_DIR/logs/module.log.1" "$MP/logs/module.log.1" 2>/dev/null
    _ilog "  [✓] 已保留上一版本的用户曲线 / HDR 偏好 / 日志开关与诊断日志"
fi

# ============ 6. 以设备原版配置为基重建模块数据文件 (核心防卡标措施) ============
# 不再直接挂载 zip 内置的静态抓取文件, 而是以当前设备自己的原版 XML 为底稿,
# 由 apply_curve.sh 在其上注入标定, 从根源上消除跨批次/跨固件结构不匹配风险
_ilog "- 正在以设备原版配置为基重建模块数据文件..."

# 6.1 Lux-Nit 曲线 (common)
if grep -q "<lux_table" "$COMMON_XML" 2>/dev/null; then
    cp -f "$COMMON_XML" "$MP/system/etc/display_brightness_config_common.xml"
    cp -f "$COMMON_XML" "$MP/system_ext/etc/display_brightness_config_common.xml"
    _ilog "  [✓] common.xml 已基于设备原版重建 ($(wc -c < "$COMMON_XML") 字节)"
else
    rm -f "$MP/system/etc/display_brightness_config_common.xml" "$MP/system_ext/etc/display_brightness_config_common.xml"
    _ilog "  [⚠] 设备 common.xml 缺少 <lux_table> 结构, 已跳过该文件挂载 (不影响开机)"
fi

# 6.2 主亮度映射表 (default) — 级别数必须与设备一致, 否则直接中止
if grep -q "<brightness_table" "$DEF_XML" 2>/dev/null; then
    cp -f "$DEF_XML" "$MP/system_ext/etc/display_brightness_config_default.xml"
    _ilog "  [✓] default.xml 已基于设备原版重建 ($(sed -n 's/.*max=\"\([0-9]*\)\".*/max=\1/p' "$DEF_XML" | head -n 1))"
else
    ui_print "❌ [错误] 设备 default.xml 缺少 <brightness_table> 结构, 强行挂载会导致卡标！"
    abort "亮度映射表结构不兼容，终止安装。"
fi

# 6.3 P_D 次级配置 (存在才重建, 缺失则移除以跳过挂载)
if [ -f "$PD_XML" ] && grep -q "<brightness_table" "$PD_XML" 2>/dev/null; then
    cp -f "$PD_XML" "$MP/my_product/vendor/etc/display_brightness_config_P_D.xml"
    _ilog "  [✓] P_D.xml 已基于设备原版重建"
else
    rm -f "$MP/my_product/vendor/etc/display_brightness_config_P_D.xml"
    _ilog "  [⚠] 设备无 P_D.xml 或结构不符, 已跳过该文件挂载 (不影响开机)"
fi

# 6.4 屏幕面板配置 — 复制设备自己的原版主屏幕面板文件 (内容与文件名均以设备为准)
mkdir -p "$MP/vendor/etc/displayconfig"
# 清理可能残留的错误面板 XML (如旧版本误嗅探的 DP 副屏配置)，避免 Magisk Magic Mount 误挂
rm -f "$MP/vendor/etc/displayconfig/"*.xml
REAL_PANEL_NAME=$(basename "$PANEL_CFG")
if grep -q "<screenBrightnessMap" "$PANEL_CFG" 2>/dev/null; then
    cp -f "$PANEL_CFG" "$MP/vendor/etc/displayconfig/$REAL_PANEL_NAME"
    _ilog "  [✓] 主屏面板配置已基于设备原版重建: $REAL_PANEL_NAME ($(wc -c < "$PANEL_CFG") 字节)"
else
    _ilog "  [⚠] 设备面板配置缺少 <screenBrightnessMap>, 已跳过该文件挂载 (不影响开机)"
fi
echo "$REAL_PANEL_NAME" > "$MP/.panel_name"
_ilog "  [✓] 主屏面板文件名映射已锁定 (.panel_name): $REAL_PANEL_NAME"

# ============ 7. 基于设备原版执行首次标定注入 ============
TB_MODULE_DIR="$MP" sh "$MP/apply_curve.sh" balanced >/dev/null 2>&1
if [ -s "$MP/system_ext/etc/display_brightness_config_default.xml" ]; then
    _ilog "  [✓] 首次标定注入完成 (详细过程见 logs/module.log)"
else
    _ilog "  [⚠] 首次标定注入未产出数据, 将以设备原版配置运行 (可稍后在 WebUI 重新保存曲线)"
fi

# ============ 8. 设置权限 ============
set_perm_recursive "$MP" 0 0 0755 0644
set_perm "$MP/apply_curve.sh" 0 0 0755
set_perm "$MP/get_telemetry.sh" 0 0 0755
set_perm "$MP/hdr_control.sh" 0 0 0755
set_perm "$MP/logger.sh" 0 0 0755
set_perm "$MP/post-fs-data.sh" 0 0 0755
set_perm "$MP/service.sh" 0 0 0755

_ilog "✅ 所有前置环境校验全部通过，模块已成功部署！"
