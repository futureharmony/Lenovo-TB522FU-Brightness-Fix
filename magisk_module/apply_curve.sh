#!/system/bin/sh
# TB522FU 自动亮度多级联动标定脚本 (平板端本地运行)
# 核心指标: 室内 10 Lux -> 滑块 30% -> 实际发光对齐用户自定义基准点
# 严格保证: 全量程双向严格单调递增，杜绝 OplusSpline NaN 除零异常与 SurfaceControl 外推溢出异常

# TB_MODULE_DIR: 安装器环境下传入模块暂存路径, 正常运行时使用固定路径
if [ -n "$TB_MODULE_DIR" ]; then
    MODDIR="$TB_MODULE_DIR"
elif [ -d "/data/adb/modules/tb522fu_brightness_fix" ]; then
    MODDIR="/data/adb/modules/tb522fu_brightness_fix"
else
    MODDIR="$(cd "$(dirname "$0")" && pwd)"
fi
. "$MODDIR/logger.sh" 2>/dev/null || true
if ! command -v blog >/dev/null 2>&1; then
    blog() { echo "[$1] $2"; }
    blog_section() { echo "=== $1 ==="; }
    blog_sync() { :; }
fi

# _do_mount <描述> <src> <dst>
_do_mount() {
    # 如果在模块安装器环境 (modules_update 或传入了 TB_MODULE_DIR), 跳过实时 bind 挂载, 仅完成磁盘文件标定写入
    if [ -n "$TB_MODULE_DIR" ] || echo "$MODDIR" | grep -q "modules_update"; then
        blog "MOUNT" "安装器/暂存环境: 跳过实时 bind 挂载 (由 post-fs-data 开机执行): $1"
        return 0
    fi
    if [ ! -f "$2" ] || [ ! -f "$3" ]; then
        blog "MOUNT" "跳过: $1 (src 或 dst 不存在)"
        return 1
    fi
    if mount -o bind "$2" "$3" 2>/dev/null; then
        blog "MOUNT" "成功: $1"
        return 0
    fi
    blog "MOUNT" "失败: $1 ($2 -> $3)"
    return 1
}

# 从设备原版 default.xml 读取真实级别范围 (跨批次自适应, 防止硬编码 10240 与
# 其他面板批次级别数不符导致调光引擎异常); 解析失败时回退到 TB522FU 标准值
read_def_range() {
    DEF_MAX=$(sed -n 's/.*max="\([0-9]*\)".*/\1/p' "$ORIG_DEF_XML" 2>/dev/null | head -n 1)
    DEF_MIN=$(sed -n 's/.*min="\([0-9]*\)".*/\1/p' "$ORIG_DEF_XML" 2>/dev/null | head -n 1)
    case "$DEF_MAX" in ''|*[!0-9]*|0) DEF_MAX=10239 ;; esac
    case "$DEF_MIN" in ''|*[!0-9]*) DEF_MIN=222 ;; esac
    if [ "$DEF_MIN" -ge "$DEF_MAX" ]; then DEF_MIN=222; DEF_MAX=10239; fi
}

ORIG_XML="/system/etc/display_brightness_config_common.xml"
TARGET_XML="$MODDIR/system/etc/display_brightness_config_common.xml"
if [ ! -f "$ORIG_XML" ]; then ORIG_XML="$TARGET_XML"; fi

ORIG_PD_XML="/my_product/vendor/etc/display_brightness_config_P_D.xml"
TARGET_PD_XML="$MODDIR/my_product/vendor/etc/display_brightness_config_P_D.xml"
if [ ! -f "$ORIG_PD_XML" ]; then ORIG_PD_XML="$TARGET_PD_XML"; fi

# 智能选定 TB522FU 主屏幕物理面板配置 (与 customize / post-fs-data 严格对齐)
detect_primary_panel() {
    local known_primary="/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
    if [ -f "$known_primary" ]; then
        echo "$known_primary"
        return 0
    fi
    if [ -f "$MODDIR/.panel_name" ]; then
        local saved_name=$(cat "$MODDIR/.panel_name" 2>/dev/null | tr -d '\r\n ')
        if [ -n "$saved_name" ] && [ -f "/vendor/etc/displayconfig/$saved_name" ]; then
            if grep -q "<highBrightnessMode" "/vendor/etc/displayconfig/$saved_name" 2>/dev/null; then
                echo "/vendor/etc/displayconfig/$saved_name"
                return 0
            fi
        fi
    fi
    if command -v dumpsys >/dev/null 2>&1; then
        local sys_id=$(dumpsys display 2>/dev/null | grep -oE 'display_id_[0-9]+\.xml' | head -n 1)
        if [ -n "$sys_id" ] && [ -f "/vendor/etc/displayconfig/$sys_id" ]; then
            echo "/vendor/etc/displayconfig/$sys_id"
            return 0
        fi
    fi
    local cand=""
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q "<highBrightnessMode" "$cand" 2>/dev/null && grep -q "<sdrHdrRatioMap" "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done
    for cand in /vendor/etc/displayconfig/display_id_*.xml; do
        [ -f "$cand" ] || continue
        if grep -q '<screenBrightnessMap interpolation="linear">' "$cand" 2>/dev/null; then
            echo "$cand"
            return 0
        fi
    done
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
ORIG_DISP_XML="${PANEL_CFG:-/vendor/etc/displayconfig/display_id_4630947077023927187.xml}"
REAL_PANEL_NAME=$(basename "$ORIG_DISP_XML")
mkdir -p "$MODDIR/vendor/etc/displayconfig" 2>/dev/null
echo "$REAL_PANEL_NAME" > "$MODDIR/.panel_name" 2>/dev/null
TARGET_DISP_XML="$MODDIR/vendor/etc/displayconfig/$REAL_PANEL_NAME"
ORIG_DEF_XML="/system_ext/etc/display_brightness_config_default.xml"
TARGET_DEF_XML="$MODDIR/system_ext/etc/display_brightness_config_default.xml"
if [ ! -f "$ORIG_DEF_XML" ]; then ORIG_DEF_XML="$TARGET_DEF_XML"; fi

MODE="${1:-balanced}"
blog_section "apply_curve 标定执行 (MODE=$MODE)"

case "$MODE" in
    "test")
        NIT=${2:-350}
        read_def_range
        TEST_LVL=$((DEF_MIN + (DEF_MAX - DEF_MIN) * 3 / 10))
        HW_BL=$(awk -v n="$NIT" 'BEGIN {
            ratio = n / 782.0;
            if (ratio < 0.01) ratio = 0.01;
            if (ratio > 1.0) ratio = 1.0;
            hw = int(ratio * 4095);
            if (hw < 10) hw = 10;
            if (hw > 4095) hw = 4095;
            print hw;
        }')
        settings put system screen_brightness_mode 0
        settings put system screen_brightness_duration 0
        settings put system screen_brightness "$TEST_LVL"
        # ===== 关键时序修复 (首次试戴不生效) =====
        # settings put screen_brightness 会触发框架异步亮度 ramp; 若紧接着直写 sysfs,
        # 框架 ramp 随后会把直写覆盖掉, 表现为「首次点击试戴不生效, 需再次调整曲线才生效」。
        # 先轮询等待背光稳定 (ramp 结束), 再直写, 之后并补一次抢占写入。
        _prev=-1
        _k=0
        while [ "$_k" -lt 12 ]; do
            _cur=$(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || echo -1)
            if [ "$_cur" = "$_prev" ]; then break; fi
            _prev="$_cur"
            _k=$((_k + 1))
            sleep 0.2
        done
        echo "$HW_BL" > /sys/class/backlight/panel0-backlight/brightness
        sleep 0.15
        echo "$HW_BL" > /sys/class/backlight/panel0-backlight/brightness
        blog "TEST" "试戴模式: $NIT Nit -> 硬件背光 $HW_BL/4095, 滑块置于 Level $TEST_LVL (30%, 已等待 ramp 稳定)"
        echo "SUCCESS: 已硬件级直接切换屏幕物理发光至 $HW_BL/4095 ($NIT Nit)，滑块同步置于 30%"
        exit 0
        ;;
    "restore")
        settings put system screen_brightness_mode 1
        echo "SUCCESS: 已恢复自动亮度托管"
        exit 0
        ;;
esac

# ==================== 锚点提取与自适应保形归一化 ====================
JSON_FILE="$MODDIR/custom_points.json"
if [ "$MODE" = "json" ] && [ -n "$2" ]; then
    JSON_FILE="$2"
fi

AWK_INIT_POINTS=$(awk -v mode="$MODE" -v json_file="$JSON_FILE" \
    -v r0="$2" -v r1="$3" -v r2="$4" -v r3="$5" -v r4="$6" \
    -v r5="$7" -v r6="$8" -v r7="$9" -v r8="${10}" -v r9="${11}" \
    -v r10="${12}" -v r11="${13}" -v r12="${14}" -v r13="${15}" -v r14="${16}" '
BEGIN {
    cnt = 0;
    if (mode == "json") {
        json = "";
        while ((getline line < json_file) > 0) {
            json = json line;
        }
        close(json_file);
        n = split(json, items, "}");
        for (i = 1; i <= n; i++) {
            item = items[i];
            if (match(item, /"slider"[ ]*:[ ]*([0-9.]+)/)) {
                s = substr(item, RSTART, RLENGTH);
                sub(/.*:[ ]*/, "", s);
                s_val = s + 0.0;
                if (match(item, /"nit"[ ]*:[ ]*([0-9.]+)/)) {
                    nit_s = substr(item, RSTART, RLENGTH);
                    sub(/.*:[ ]*/, "", nit_s);
                    n_val = nit_s + 0.0;
                    cnt++;
                    raw_s[cnt] = s_val;
                    raw_n[cnt] = n_val;
                }
            }
        }
    } else if (mode == "raw" && r14 != "") {
        cnt = 5;
        raw_s[1] = 0.0;   raw_n[1] = r0 + 0.0;
        raw_s[2] = 15.0;  raw_n[2] = r4 + 0.0;
        raw_s[3] = 30.0;  raw_n[3] = r5 + 0.0;
        raw_s[4] = 60.0;  raw_n[4] = r10 + 0.0;
        raw_s[5] = 100.0; raw_n[5] = r14 + 0.0;
    } else if (mode == "bright") {
        cnt = 5;
        raw_s[1] = 0.0;   raw_n[1] = 30.0;
        raw_s[2] = 15.0;  raw_n[2] = 200.0;
        raw_s[3] = 30.0;  raw_n[3] = 400.0;
        raw_s[4] = 60.0;  raw_n[4] = 600.0;
        raw_s[5] = 100.0; raw_n[5] = 750.0;
    } else if (mode == "gentle") {
        cnt = 5;
        raw_s[1] = 0.0;   raw_n[1] = 15.0;
        raw_s[2] = 15.0;  raw_n[2] = 120.0;
        raw_s[3] = 30.0;  raw_n[3] = 280.0;
        raw_s[4] = 60.0;  raw_n[4] = 480.0;
        raw_s[5] = 100.0; raw_n[5] = 750.0;
    } else {
        cnt = 5;
        raw_s[1] = 0.0;   raw_n[1] = 20.0;
        raw_s[2] = 15.0;  raw_n[2] = 150.0;
        raw_s[3] = 30.0;  raw_n[3] = 350.0;
        raw_s[4] = 60.0;  raw_n[4] = 550.0;
        raw_s[5] = 100.0; raw_n[5] = 750.0;
    }

    if (cnt < 2) {
        cnt = 5;
        raw_s[1] = 0.0;   raw_n[1] = 20.0;
        raw_s[2] = 15.0;  raw_n[2] = 150.0;
        raw_s[3] = 30.0;  raw_n[3] = 350.0;
        raw_s[4] = 60.0;  raw_n[4] = 550.0;
        raw_s[5] = 100.0; raw_n[5] = 750.0;
    }

    # 按 slider 升序排序
    for (i = 2; i <= cnt; i++) {
        cur_s = raw_s[i]; cur_n = raw_n[i];
        j = i - 1;
        while (j >= 1 && raw_s[j] > cur_s) {
            raw_s[j+1] = raw_s[j];
            raw_n[j+1] = raw_n[j];
            j--;
        }
        raw_s[j+1] = cur_s;
        raw_n[j+1] = cur_n;
    }

    # 端点归一化与钳制 (与 WebUI 限制严格一致):
    #   极暗底线 (slider 0):   [2, 80] Nit  — 最暗保护, 防极暗 PWM 闪烁 / AOD 异常
    #   强光满格 (slider 100): [400, 782] Nit — 782 为常规 SDR 上限, 超出进入 HBM 阳光模式
    # 说明: 崩溃防护的真正来源是「低端平台令模型选中安全的 ExponentModel」,
    #       而非压缩顶端 nit; 故此处可安全放开到 782 Nit。
    raw_s[1] = 0.0;
    raw_s[cnt] = 100.0;
    if (raw_n[1] < 2.0) raw_n[1] = 2.0;
    if (raw_n[1] > 80.0) raw_n[1] = 80.0;
    if (raw_n[cnt] > 782.0) raw_n[cnt] = 782.0;
    if (raw_n[cnt] < 400.0) raw_n[cnt] = 400.0;

    # 严格单调递增双向校验 (双向断言，杜绝任何倒挂)
    for (i = 2; i <= cnt; i++) {
        if (raw_n[i] < raw_n[i-1] + 0.5) raw_n[i] = raw_n[i-1] + 0.5;
    }
    for (i = cnt - 1; i >= 1; i--) {
        if (raw_n[i] > raw_n[i+1] - 0.5) raw_n[i] = raw_n[i+1] - 0.5;
    }

    for (i = 1; i <= cnt; i++) {
        printf "%.1f,%.2f ", raw_s[i], raw_n[i];
    }
}')

blog "APPLY" "有效控制点归一化结果: $AWK_INIT_POINTS"

mkdir -p "$MODDIR/system/etc"
mkdir -p "$MODDIR/system_ext/etc"
mkdir -p "$MODDIR/my_product/vendor/etc"
mkdir -p "$MODDIR/vendor/etc/displayconfig"

# =========================================================================
# 1. 写入 display_brightness_config_common.xml (更新 lux_table 3 和 43)
# =========================================================================
awk -v pts_str="$AWK_INIT_POINTS" '
function init_pts(str,   n, arr, i, pair) {
    n = split(str, arr, " ");
    NUM_PTS = n;
    for (i = 1; i <= n; i++) {
        split(arr[i], pair, ",");
        S_ARR[i] = pair[1] + 0.0;
        N_ARR[i] = pair[2] + 0.0;
    }
}
function evaluate_nit(s,   i, t, st) {
    if (s <= S_ARR[1]) return N_ARR[1];
    if (s >= S_ARR[NUM_PTS]) return N_ARR[NUM_PTS];
    for (i = 1; i < NUM_PTS; i++) {
        if (s <= S_ARR[i+1]) {
            t = (s - S_ARR[i]) / (S_ARR[i+1] - S_ARR[i]);
            st = 0.3 * t + 0.7 * (t * t * (3.0 - 2.0 * t));
            return N_ARR[i] + (N_ARR[i+1] - N_ARR[i]) * st;
        }
    }
    return N_ARR[NUM_PTS];
}
BEGIN {
    init_pts(pts_str);
    lux_arr[1]=0;    s_map[1]=0.0;
    lux_arr[2]=2;    s_map[2]=5.0;
    lux_arr[3]=4;    s_map[3]=10.0;
    lux_arr[4]=6;    s_map[4]=16.0;
    lux_arr[5]=8;    s_map[5]=23.0;
    lux_arr[6]=10;   s_map[6]=30.0;
    lux_arr[7]=15;   s_map[7]=36.0;
    lux_arr[8]=20;   s_map[8]=42.0;
    lux_arr[9]=30;   s_map[9]=50.0;
    lux_arr[10]=50;  s_map[10]=58.0;
    lux_arr[11]=100; s_map[11]=66.0;
    lux_arr[12]=500; s_map[12]=76.0;
    lux_arr[13]=1000; s_map[13]=84.0;
    lux_arr[14]=5000; s_map[14]=93.0;
    lux_arr[15]=8600; s_map[15]=100.0;
    # 超高 lux 安全平台: 阻止框架在 >8600 lux 时做线性外推
    # 没有此平台时, 10000+ lux 外推会产生 nit > mMaxPanelBrightness → crash
    lux_arr[16]=200000; s_map[16]=100.0;
    NUM_LUX = 16;

    prev = 1.0;
    for (i = 1; i <= NUM_LUX; i++) {
        n = sprintf("%.2f", evaluate_nit(s_map[i])) + 0.0;
        if (n < prev + 0.5) n = prev + 0.5;
        p_nits[i] = n;
        prev = n;
    }
    if (p_nits[NUM_LUX] > N_ARR[NUM_PTS]) p_nits[NUM_LUX] = N_ARR[NUM_PTS];
    # 安全钳制: 最后两个点都钳制到安全天花板以下
    if (p_nits[NUM_LUX] > 750.0) p_nits[NUM_LUX] = 750.0;
    if (p_nits[NUM_LUX-1] > 750.0) p_nits[NUM_LUX-1] = 750.0;
    for (i = NUM_LUX - 1; i >= 1; i--) {
        if (p_nits[i] > p_nits[i+1] - 0.5) p_nits[i] = p_nits[i+1] - 0.5;
    }

    in_table = 0;
    in_hbm = 0;
}
/<lux_table id="(3|43)">/ {
    in_table = 1;
    print $0;
    print "        <!-- auto calibrated for TB522FU strictly monotonic -->";
    for (i = 1; i <= NUM_LUX; i++) {
        printf "        <lux>   %4d , %6.2f </lux>\n", lux_arr[i], p_nits[i];
    }
    next;
}
in_table && /<\/lux_table>/ {
    in_table = 0;
    print $0;
    next;
}
/<hbm_lux_table id="(3|43)">/ {
    in_hbm = 1;
    print $0;
    print "        <!-- auto calibrated safe HBM ceiling for TB522FU -->";
    hbm_cap = p_nits[15];
    if (hbm_cap > 750.0) hbm_cap = 750.0;
    h1 = sprintf("%.2f", hbm_cap * 0.85) + 0.0;
    h2 = sprintf("%.2f", hbm_cap * 0.90) + 0.0;
    h3 = sprintf("%.2f", hbm_cap * 0.95) + 0.0;
    h4 = sprintf("%.2f", hbm_cap * 0.98) + 0.0;
    h5 = sprintf("%.2f", hbm_cap * 0.995) + 0.0;
    # 超高 lux 安全平台: 阻止 HBM 模式在 >80101 lux 时做线性外推
    h6 = sprintf("%.2f", hbm_cap) + 0.0;
    if (h1 >= h2) h2 = h1 + 0.5;
    if (h2 >= h3) h3 = h2 + 0.5;
    if (h3 >= h4) h4 = h3 + 0.5;
    if (h4 >= h5) h5 = h4 + 0.5;
    if (h5 >= h6) h5 = h6 - 0.5;
    printf "        <lux>10101 ,%6.2f</lux>\n", h1;
    printf "        <lux>30101 ,%6.2f</lux>\n", h2;
    printf "        <lux>40101 ,%6.2f</lux>\n", h3;
    printf "        <lux>60101 ,%6.2f</lux>\n", h4;
    printf "        <lux>80101 ,%6.2f</lux>\n", h5;
    printf "        <lux>200000,%6.2f</lux>\n", h6;
    next;
}
in_hbm && /<\/hbm_lux_table>/ {
    in_hbm = 0;
    print $0;
    next;
}
!in_table && !in_hbm { print $0; }
' "$ORIG_XML" > "$TARGET_XML.tmp"

if [ -s "$TARGET_XML.tmp" ]; then
    cat "$TARGET_XML.tmp" > "$TARGET_XML"
    rm -f "$TARGET_XML.tmp"
    chmod 644 "$TARGET_XML"
    chcon u:object_r:system_file:s0 "$TARGET_XML" 2>/dev/null || true
    blog "APPLY" "common.xml 标定写入成功 ($(wc -c < "$TARGET_XML") 字节, $(grep -c '<lux>' "$TARGET_XML") 个 lux 点)"
    _do_mount "Lux-Nit 曲线 (system common)" "$TARGET_XML" "$ORIG_XML"
else
    blog "APPLY" "错误: common.xml 标定生成失败 (输出为空), 保留原文件不动"
fi

# =========================================================================
# 2. 写入 display_brightness_config_P_D.xml (标定 2048 级: 严格单调)
# =========================================================================
PD_SRC="$ORIG_PD_XML"
if [ ! -f "$PD_SRC" ]; then PD_SRC="$TARGET_PD_XML"; fi

awk -v pts_str="$AWK_INIT_POINTS" '
function init_pts(str,   n, arr, i, pair) {
    n = split(str, arr, " ");
    NUM_PTS = n;
    for (i = 1; i <= n; i++) {
        split(arr[i], pair, ",");
        S_ARR[i] = pair[1] + 0.0;
        N_ARR[i] = pair[2] + 0.0;
    }
}
function evaluate_nit(s,   i, t, st) {
    if (s <= S_ARR[1]) return N_ARR[1];
    if (s >= S_ARR[NUM_PTS]) return N_ARR[NUM_PTS];
    for (i = 1; i < NUM_PTS; i++) {
        if (s <= S_ARR[i+1]) {
            t = (s - S_ARR[i]) / (S_ARR[i+1] - S_ARR[i]);
            st = 0.3 * t + 0.7 * (t * t * (3.0 - 2.0 * t));
            return N_ARR[i] + (N_ARR[i+1] - N_ARR[i]) * st;
        }
    }
    return N_ARR[NUM_PTS];
}
BEGIN {
    init_pts(pts_str);
    in_table = 0;
}
/<brightness_table max="1745" min="2">/ {
    in_table = 1;
    print $0;
    print "        <level> 0    ,0    ,  0.000    ,1.00 </level>";
    n_min = sprintf("%.3f", N_ARR[1]) + 0.0;
    printf "        <level> 1    ,1    ,%7.3f    ,1.00 </level>\n", n_min;
    prev_nit = n_min;
    for (L = 2; L <= 1745; L++) {
        slider = sqrt(L / 1745.0) * 100.0;
        nit = evaluate_nit(slider);
        nit_rounded = sprintf("%.3f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.3f", prev_nit + 0.002) + 0.0;
        }
        prev_nit = nit_rounded;
        printf "        <level> %4d    ,%4d    ,%7.3f    ,1.00 </level>\n", L, L, nit_rounded;
    }
    for (L = 1746; L <= 2047; L++) {
        ratio = (L - 1745.0) / (2047.0 - 1745.0);
        nit = prev_nit + (1100.0 - prev_nit) * ratio;
        nit_rounded = sprintf("%.3f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.3f", prev_nit + 0.002) + 0.0;
        }
        prev_nit = nit_rounded;
        printf "        <level> %4d    ,%4d    ,%7.3f    ,1.00 </level>\n", L, L, nit_rounded;
    }
    next;
}
in_table && /<\/brightness_table>/ {
    in_table = 0;
    print $0;
    next;
}
!in_table { print $0; }
' "$PD_SRC" > "$TARGET_PD_XML.tmp"

if [ -s "$TARGET_PD_XML.tmp" ]; then
    cat "$TARGET_PD_XML.tmp" > "$TARGET_PD_XML"
    rm -f "$TARGET_PD_XML.tmp"
    chmod 644 "$TARGET_PD_XML"
    chcon u:object_r:system_file:s0 "$TARGET_PD_XML" 2>/dev/null || true
    blog "APPLY" "P_D 标定写入成功 ($(wc -c < "$TARGET_PD_XML") 字节, $(grep -c '<level>' "$TARGET_PD_XML") 个 level)"
    _do_mount "P_D 次级配置" "$TARGET_PD_XML" "$ORIG_PD_XML"
fi

# =========================================================================
# 3. 写入 vendor display_id_*.xml (物理屏幕面板光学特性安全保护)
#    核心准则: 保留原厂 50 个真实物理光学采样点, 仅将下界安全定在 0.0000 Nit,
#    将上界定在 805.0000 Nit 冗余天花板, 100% 杜绝 Android Framework 样条反向负数外推
#    与正向 > 1.0f 溢出外推引发的 SurfaceControl 致命崩溃！
# =========================================================================
DISP_SRC="$ORIG_DISP_XML"
if [ ! -f "$DISP_SRC" ]; then DISP_SRC="$TARGET_DISP_XML"; fi

awk '
BEGIN { in_map = 0; point_idx = 0; }
/<screenBrightnessMap interpolation="linear">/ {
    in_map = 1;
    print $0;
    next;
}
in_map && /<point>/ {
    in_point = 1;
    point_idx++;
    buf = $0 "\n";
    next;
}
in_map && in_point {
    buf = buf $0 "\n";
    if (/<\/point>/) {
        in_point = 0;
        if (point_idx == 1) {
            # 绝对安全底线: 硬件 0.0000 电平对应 0.0000 Nit, 彻底切断任何负数外推
            sub(/<nits>[0-9.]+<\/nits>/, "<nits>0.0000</nits>", buf);
        }
        if (buf ~ /<value>1\.0000<\/value>/) {
            # 绝对安全天花板: 硬件 1.0000 电平声明 805.0000 Nit 冗余, 彻底切断任何 > 1.0f 溢出外推
            sub(/<nits>[0-9.]+<\/nits>/, "<nits>805.0000</nits>", buf);
        }
        printf "%s", buf;
    }
    next;
}
in_map && /<\/screenBrightnessMap>/ {
    in_map = 0;
    print $0;
    next;
}
{ print $0; }
' "$DISP_SRC" > "$TARGET_DISP_XML.tmp"

if [ -s "$TARGET_DISP_XML.tmp" ]; then
    cat "$TARGET_DISP_XML.tmp" > "$TARGET_DISP_XML"
    rm -f "$TARGET_DISP_XML.tmp"
    chmod 644 "$TARGET_DISP_XML"
    chcon u:object_r:vendor_configs_file:s0 "$TARGET_DISP_XML" 2>/dev/null || true
    blog "APPLY" "面板配置安全加固写入成功 ($(wc -c < "$TARGET_DISP_XML") 字节)"
    for f in "$MODDIR/vendor/etc/displayconfig/"*.xml; do
        [ -f "$f" ] || continue
        if [ "$(basename "$f")" != "$REAL_PANEL_NAME" ]; then
            rm -f "$f"
        fi
    done
    _do_mount "面板配置 ($REAL_PANEL_NAME)" "$TARGET_DISP_XML" "$ORIG_DISP_XML"
else
    blog "APPLY" "警告: 面板配置标定生成失败, 保留原文件不动"
fi

# =========================================================================
# 4. 生成全量程 display_brightness_config_default.xml (10240 阶全量程映射)
#    采用保形双向扫描算法，严格保证 Level 0~10239 绝对单调递增且最高点严格锁定用户设定的最大发光值，绝不越界！
# =========================================================================
read_def_range
blog "APPLY" "default.xml 级别范围自适应: max=$DEF_MAX min=$DEF_MIN (读取自设备原版表头)"

awk -v pts_str="$AWK_INIT_POINTS" -v maxl="$DEF_MAX" -v minl="$DEF_MIN" '
function init_pts(str,   n, arr, i, pair) {
    n = split(str, arr, " ");
    NUM_PTS = n;
    for (i = 1; i <= n; i++) {
        split(arr[i], pair, ",");
        S_ARR[i] = pair[1] + 0.0;
        N_ARR[i] = pair[2] + 0.0;
    }
}
function evaluate_nit(s,   i, t, st) {
    if (s <= S_ARR[1]) return N_ARR[1];
    if (s >= S_ARR[NUM_PTS]) return N_ARR[NUM_PTS];
    for (i = 1; i < NUM_PTS; i++) {
        if (s <= S_ARR[i+1]) {
            t = (s - S_ARR[i]) / (S_ARR[i+1] - S_ARR[i]);
            st = 0.3 * t + 0.7 * (t * t * (3.0 - 2.0 * t));
            return N_ARR[i] + (N_ARR[i+1] - N_ARR[i]) * st;
        }
    }
    return N_ARR[NUM_PTS];
}
BEGIN {
    init_pts(pts_str);
    maxl = maxl + 0;
    minl = minl + 0;

    printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n    <!-- calibrated by futureharmony for TB522FU ColorOS 16 -->\n    <version>20260914</version>\n    <lux_table_mode>3</lux_table_mode>\n    <hbm_lux_table_mode>3</hbm_lux_table_mode>\n    <brightness_table max=\"%d\" min=\"%d\">\n", maxl, minl;

    # 顶端取用户曲线最大值 (后端/前端均已钳制 <= 782, 即常规 SDR 上限)
    target_top_nit = N_ARR[NUM_PTS];

    for (L = 0; L <= maxl; L++) {
        if (L == 0) {
            raw_nit[L] = 0.0;
        } else if (L < minl) {
            # 低端发光平台 (防崩关键):
            # OplusDisplayBrightnessModeStrategy.sniffDisplayBrightnessModel() 依据
            # brightness_table[10] 与 brightness_table[20] 的 Nit 差值选择亮度模型:
            #   差值 < 1.0  -> ExponentModel (安全: backlight/4095, 恒 <= 1.0)
            #   差值 >= 1.0 -> LinearModel   (致命: level/4095, level>4095 时 displayBrightness > 1.0 崩溃)
            # 因此低端必须采用平缓的三次缓升, 令 10 级与 20 级 Nit 差值远小于 1.0
            ratio = L / (minl - 1 + 0.0);
            low_floor = 2.0;
            if (low_floor > N_ARR[1]) low_floor = N_ARR[1];
            raw_nit[L] = low_floor + (N_ARR[1] - low_floor) * (ratio * ratio * ratio);
        } else {
            slider = ((L - minl) / (maxl - minl + 0.0)) * 100.0;
            raw_nit[L] = evaluate_nit(slider);
        }
    }

    # 前向扫描: 保证每一级严格单调递增
    fmt_nit[0] = 0.0;
    prev = 0.0;
    for (L = 1; L < maxl; L++) {
        val = sprintf("%.3f", raw_nit[L]) + 0.0;
        if (val <= prev) val = sprintf("%.3f", prev + 0.001) + 0.0;
        fmt_nit[L] = val;
        prev = val;
    }
    fmt_nit[maxl] = sprintf("%.3f", target_top_nit) + 0.0;

    # 后向扫描: 严防任何级别超出最大发光值设定
    for (L = maxl - 1; L >= 1; L--) {
        if (fmt_nit[L] >= fmt_nit[L+1]) {
            fmt_nit[L] = sprintf("%.3f", fmt_nit[L+1] - 0.001) + 0.0;
        }
    }

    # 背光列 = nit / 782 * 4095 (线性映射), 与「实时试戴」完全一致。
    # 原理: 原厂 OplusDisplayBrightnessExponentModel 实际下发驱动的亮度为
    #       backlight = 背光列[level] / 背光列末值, 而「试戴」直接写 nit/782*4095。
    #       故背光列必须与 nit 线性对应, 自动亮度才能达到用户设定的真实发光值。
    hw_arr[0] = 0;
    for (L = 1; L <= maxl; L++) {
        hw_arr[L] = int(fmt_nit[L] / 782.0 * 4095.0 + 0.5);
        if (hw_arr[L] < 1) hw_arr[L] = 1;
        if (hw_arr[L] > 4095) hw_arr[L] = 4095;
        if (hw_arr[L] < hw_arr[L-1]) hw_arr[L] = hw_arr[L-1];
    }

    for (L = 0; L <= maxl; L++) {
        printf "        <level>%4d   ,%4d   ,%7.3f,1.00000</level>\n", L, hw_arr[L], fmt_nit[L];
    }
    print "    </brightness_table>\n</root>";
}
' > "$TARGET_DEF_XML.tmp"

if [ -s "$TARGET_DEF_XML.tmp" ]; then
    cat "$TARGET_DEF_XML.tmp" > "$TARGET_DEF_XML"
    rm -f "$TARGET_DEF_XML.tmp"
    chmod 644 "$TARGET_DEF_XML"
    chcon u:object_r:system_file:s0 "$TARGET_DEF_XML" 2>/dev/null || true
    blog "APPLY" "default.xml 标定写入成功 ($(wc -c < "$TARGET_DEF_XML") 字节, $(grep -c '<level>' "$TARGET_DEF_XML") 个 level)"
    _do_mount "主亮度映射表 (default.xml)" "$TARGET_DEF_XML" "$ORIG_DEF_XML"
else
    blog "APPLY" "错误: default.xml 标定生成失败 (输出为空), 保留原文件不动"
fi

# 同步 common 到 system_ext
cp -f "$TARGET_XML" "$MODDIR/system_ext/etc/display_brightness_config_common.xml" 2>/dev/null
_do_mount "Lux-Nit 曲线 (system_ext common)" "$TARGET_XML" "/system_ext/etc/display_brightness_config_common.xml"

# 重置异常拖动学习缓存至 30% 黄金基准 (级别数随设备原版自适应)
ANCHOR_LVL=$((DEF_MIN + (DEF_MAX - DEF_MIN) * 3 / 10))
settings put system screen_brightness "$ANCHOR_LVL" 2>/dev/null
settings put system screen_brightness_duration 0 2>/dev/null
blog "APPLY" "滑块学习缓存重置至 30% 基准 (Level $ANCHOR_LVL)"

blog_sync
echo "SUCCESS: 自动亮度联动映射已注入底层系统！"
echo "联动标定: 室内光(10Lux) -> 控制栏滑块(30%) -> 用户自定发光基准"
echo "单调安全: 驱动面板配置声明绝对安全上下界 [0.0, 805.0] Nit，彻底杜绝样条外推异常与系统崩溃！"
