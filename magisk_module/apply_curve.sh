#!/system/bin/sh
# TB522FU 自动亮度三级联动标定脚本 (平板端本地运行)
# 核心指标: 室内 10 Lux -> 滑块 30% -> 实际发光 350 Nit
# 严格保证: 所有控制点双向严格单调递增，杜绝 OplusSpline NaN 除零异常

# TB_MODULE_DIR: 安装器环境下传入模块暂存路径, 正常运行时使用固定路径
MODDIR="${TB_MODULE_DIR:-/data/adb/modules/tb522fu_brightness_fix}"
. "$MODDIR/logger.sh" 2>/dev/null

# _do_mount <描述> <src> <dst>
_do_mount() {
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
ORIG_PD_XML="/my_product/vendor/etc/display_brightness_config_P_D.xml"
TARGET_PD_XML="$MODDIR/my_product/vendor/etc/display_brightness_config_P_D.xml"
SYS_DISP=$(ls /vendor/etc/displayconfig/display_id_*.xml 2>/dev/null | head -n 1)
ORIG_DISP_XML="${SYS_DISP:-/vendor/etc/displayconfig/display_id_4630947077023927187.xml}"
TARGET_DISP_XML="$MODDIR/vendor/etc/displayconfig/$(basename "$ORIG_DISP_XML")"
if [ ! -f "$TARGET_DISP_XML" ]; then
    TARGET_DISP_XML="$MODDIR/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
fi
ORIG_DEF_XML="/system_ext/etc/display_brightness_config_default.xml"
TARGET_DEF_XML="$MODDIR/system_ext/etc/display_brightness_config_default.xml"

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
        settings put system screen_brightness "$TEST_LVL"
        echo "$HW_BL" > /sys/class/backlight/panel0-backlight/brightness
        blog "TEST" "试戴模式: $NIT Nit -> 硬件背光 $HW_BL/4095, 滑块置于 Level $TEST_LVL (30%)"
        echo "SUCCESS: 已硬件级直接切换屏幕物理发光至 $HW_BL/4095 ($NIT Nit)，滑块同步置于 30%"
        exit 0
        ;;
    "restore")
        settings put system screen_brightness_mode 1
        echo "SUCCESS: 已恢复自动亮度托管"
        exit 0
        ;;
    "json")
        JSON_FILE="${2:-$MODDIR/custom_points.json}"
        if [ -f "$JSON_FILE" ]; then
            POINTS_VAL=$(awk '
            function get_val(s, key, arr) {
                if (match(s, "\"" key "\"[ ]*:[ ]*([0-9.]+)")) {
                    sub(/.*"nit"[ ]*:[ ]*/, "", s);
                    sub(/[^0-9.].*/, "", s);
                    return s;
                }
                return "";
            }
            { json = json $0 }
            END {
                n = split(json, items, "}");
                for (i = 1; i <= n; i++) {
                    nit = get_val(items[i], "nit");
                    if (nit != "") {
                        printf "%.2f ", nit;
                    }
                }
            }' "$JSON_FILE")
            set -- $POINTS_VAL
            if [ $# -ge 5 ]; then
                blog "APPLY-JSON" "解析自定义锚点成功 (共 $# 个值): $POINTS_VAL"
                N_0=$1; N_10=$3; N_100=$4; N_8600=$5
                P_0=$N_0
                P_2=$(awk -v n0="$N_0" -v n10="$N_10" 'BEGIN { printf "%.2f", n0 + (n10 - n0)*0.35 }')
                P_4=$(awk -v n0="$N_0" -v n10="$N_10" 'BEGIN { printf "%.2f", n0 + (n10 - n0)*0.60 }')
                P_6=$(awk -v n0="$N_0" -v n10="$N_10" 'BEGIN { printf "%.2f", n0 + (n10 - n0)*0.80 }')
                P_8=$(awk -v n0="$N_0" -v n10="$N_10" 'BEGIN { printf "%.2f", n0 + (n10 - n0)*0.92 }')
                P_10=$N_10
                P_15=$(awk -v n10="$N_10" -v n100="$N_100" 'BEGIN { printf "%.2f", n10 + (n100 - n10)*0.20 }')
                P_20=$(awk -v n10="$N_10" -v n100="$N_100" 'BEGIN { printf "%.2f", n10 + (n100 - n10)*0.35 }')
                P_30=$(awk -v n10="$N_10" -v n100="$N_100" 'BEGIN { printf "%.2f", n10 + (n100 - n10)*0.60 }')
                P_50=$(awk -v n10="$N_10" -v n100="$N_100" 'BEGIN { printf "%.2f", n10 + (n100 - n10)*0.85 }')
                P_100=$N_100
                P_500=$(awk -v n100="$N_100" -v n8600="$N_8600" 'BEGIN { printf "%.2f", n100 + (n8600 - n100)*0.50 }')
                P_1000=$(awk -v n100="$N_100" -v n8600="$N_8600" 'BEGIN { printf "%.2f", n100 + (n8600 - n100)*0.80 }')
                P_5000=$(awk -v n100="$N_100" -v n8600="$N_8600" 'BEGIN { printf "%.2f", n100 + (n8600 - n100)*0.95 }')
                P_8600=$N_8600
            else
                P_0=2; P_2=20; P_4=60; P_6=130; P_8=230; P_10=350; P_15=390; P_20=420; P_30=460; P_50=510; P_100=570; P_500=640; P_1000=700; P_5000=750; P_8600=782
            fi
        else
            P_0=2; P_2=20; P_4=60; P_6=130; P_8=230; P_10=350; P_15=390; P_20=420; P_30=460; P_50=510; P_100=570; P_500=640; P_1000=700; P_5000=750; P_8600=782
        fi
        ;;
    "raw")
        P_0=${2:-2}
        P_2=${3:-20}
        P_4=${4:-60}
        P_6=${5:-130}
        P_8=${6:-230}
        P_10=${7:-350}
        P_15=${8:-390}
        P_20=${9:-420}
        P_30=${10:-460}
        P_50=${11:-510}
        P_100=${12:-570}
        P_500=${13:-640}
        P_1000=${14:-700}
        P_5000=${15:-750}
        P_8600=${16:-782}
        ;;
    "bright")
        # 通透偏好: 10 Lux 对应 400 Nit (滑块 35%)
        P_0=3; P_2=30; P_4=90; P_6=180; P_8=290; P_10=400; P_15=440; P_20=470; P_30=510; P_50=560; P_100=620; P_500=680; P_1000=730; P_5000=765; P_8600=782
        ;;
    "gentle")
        # 柔和偏好: 10 Lux 对应 280 Nit (滑块 25%)
        P_0=2; P_2=15; P_4=45; P_6=95; P_8=180; P_10=280; P_15=330; P_20=370; P_30=420; P_50=480; P_100=550; P_500=630; P_1000=690; P_5000=750; P_8600=782
        ;;
    *)
        # 方案 A 均衡官方标定: 10 Lux 对应 350 Nit (滑块 30%)
        P_0=2; P_2=20; P_4=60; P_6=130; P_8=230; P_10=350; P_15=390; P_20=420; P_30=460; P_50=510; P_100=570; P_500=640; P_1000=700; P_5000=750; P_8600=782
        ;;
esac

# 强制严格双向单调递增验证与钳制 (严格递增防止 OplusSpline 崩溃)
awk_validate=$(awk -v p0="$P_0" -v p2="$P_2" -v p4="$P_4" -v p6="$P_6" -v p8="$P_8" \
    -v p10="$P_10" -v p15="$P_15" -v p20="$P_20" -v p30="$P_30" -v p50="$P_50" \
    -v p100="$P_100" -v p500="$P_500" -v p1000="$P_1000" -v p5000="$P_5000" -v p8600="$P_8600" 'BEGIN {
    arr[1]=p0; arr[2]=p2; arr[3]=p4; arr[4]=p6; arr[5]=p8;
    arr[6]=p10; arr[7]=p15; arr[8]=p20; arr[9]=p30; arr[10]=p50;
    arr[11]=p100; arr[12]=p500; arr[13]=p1000; arr[14]=p5000; arr[15]=p8600;

    prev = 1.0;
    for (i = 1; i <= 15; i++) {
        val = arr[i] + 0.0;
        if (val < prev + 0.5) val = prev + 0.5;
        arr[i] = val;
        prev = val;
    }
    if (arr[15] > 782.0) arr[15] = 782.0;
    for (i = 14; i >= 1; i--) {
        if (arr[i] > arr[i+1] - 0.5) arr[i] = arr[i+1] - 0.5;
    }
    for (i = 1; i <= 15; i++) {
        printf "%.2f ", arr[i];
    }
}')

set -- $awk_validate
P_0=$1; P_2=$2; P_4=$3; P_6=$4; P_8=$5
P_10=$6; P_15=$7; P_20=$8; P_30=$9; P_50=${10}
P_100=${11}; P_500=${12}; P_1000=${13}; P_5000=${14}; P_8600=${15}
blog "APPLY" "单调钳制后 15 点标定: $P_0 $P_2 $P_4 $P_6 $P_8 $P_10 $P_15 $P_20 $P_30 $P_50 $P_100 $P_500 $P_1000 $P_5000 $P_8600"

mkdir -p "$MODDIR/system/etc"
mkdir -p "$MODDIR/system_ext/etc"
mkdir -p "$MODDIR/my_product/vendor/etc"
mkdir -p "$MODDIR/vendor/etc/displayconfig"

# 1. 写入 display_brightness_config_common.xml (更新 lux_table 3 和 43)
awk -v p0="$P_0" -v p2="$P_2" -v p4="$P_4" -v p6="$P_6" -v p8="$P_8" \
    -v p10="$P_10" -v p15="$P_15" -v p20="$P_20" -v p30="$P_30" -v p50="$P_50" \
    -v p100="$P_100" -v p500="$P_500" -v p1000="$P_1000" -v p5000="$P_5000" -v p8600="$P_8600" '
    BEGIN { in_table = 0 }
    /<lux_table id="(3|43)">/ {
        in_table = 1
        print $0
        print "        <!-- auto calibrated for TB522FU strictly monotonic -->"
        printf "        <lux>      0 , %6.2f </lux>\n", p0
        printf "        <lux>      2 , %6.2f </lux>\n", p2
        printf "        <lux>      4 , %6.2f </lux>\n", p4
        printf "        <lux>      6 , %6.2f </lux>\n", p6
        printf "        <lux>      8 , %6.2f </lux>\n", p8
        printf "        <lux>     10 , %6.2f </lux>\n", p10
        printf "        <lux>     15 , %6.2f </lux>\n", p15
        printf "        <lux>     20 , %6.2f </lux>\n", p20
        printf "        <lux>     30 , %6.2f </lux>\n", p30
        printf "        <lux>     50 , %6.2f </lux>\n", p50
        printf "        <lux>    100 , %6.2f </lux>\n", p100
        printf "        <lux>    500 , %6.2f </lux>\n", p500
        printf "        <lux>   1000 , %6.2f </lux>\n", p1000
        printf "        <lux>   5000 , %6.2f </lux>\n", p5000
        printf "        <lux>   8600 , %6.2f </lux>\n", p8600
        next
    }
    in_table && /<\/lux_table>/ {
        in_table = 0
        print $0
        next
    }
    !in_table { print $0 }
' "$ORIG_XML" > "$TARGET_XML.tmp"

if [ -s "$TARGET_XML.tmp" ]; then
    cat "$TARGET_XML.tmp" > "$TARGET_XML"
    rm -f "$TARGET_XML.tmp"
    chmod 644 "$TARGET_XML"
    chcon u:object_r:system_file:s0 "$TARGET_XML"
    blog "APPLY" "common.xml 标定写入成功 ($(wc -c < "$TARGET_XML") 字节, $(grep -c '<lux>' "$TARGET_XML") 个 lux 点)"
    _do_mount "Lux-Nit 曲线 (system common)" "$TARGET_XML" "$ORIG_XML"
else
    blog "APPLY" "错误: common.xml 标定生成失败 (输出为空), 保留原文件不动"
fi

# 2. 写入 display_brightness_config_P_D.xml (标定 2048 级: 严格递增)
PD_SRC="$ORIG_PD_XML"
if [ ! -f "$PD_SRC" ]; then PD_SRC="$TARGET_PD_XML"; fi

# 结构嗅探: 该表采用字面量匹配, 固件结构不同时原样保留并记录 (不强行注入)
if grep -q '<brightness_table max="1745" min="2">' "$PD_SRC" 2>/dev/null; then
    blog "APPLY" "P_D 结构嗅探: 匹配 1745 级标尺, 执行标定注入"
else
    blog "APPLY" "警告: P_D 源文件结构与本模块预期不符 (缺少 1745 级标尺头), 将原样保留以防异常"
fi

awk -v p0="$P_0" -v p30="$P_10" -v p60="550.0" -v p100="$P_8600" '
function evaluate_nit(slider,   t, smooth_t) {
    if (slider <= 0.0) return p0 + 0.0;
    if (slider <= 30.0) {
        t = slider / 30.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p0 + 0.0) + ((p30 + 0.0) - (p0 + 0.0)) * smooth_t;
    }
    if (slider <= 60.0) {
        t = (slider - 30.0) / 30.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p30 + 0.0) + ((p60 + 0.0) - (p30 + 0.0)) * smooth_t;
    }
    if (slider <= 100.0) {
        t = (slider - 60.0) / 40.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p60 + 0.0) + ((p100 + 0.0) - (p60 + 0.0)) * smooth_t;
    }
    return p100 + 0.0;
}
BEGIN {
    in_table = 0;
}
/<brightness_table max="1745" min="2">/ {
    in_table = 1;
    print $0;
    print "        <level> 0    ,0    ,  0.000    ,1.00 </level>";
    n_min = sprintf("%.3f", p0 + 0.0) + 0.0;
    printf "        <level> 1    ,1    ,%7.3f    ,1.00 </level>\n", n_min;
    prev_nit = n_min;
    for (L = 2; L <= 1745; L++) {
        slider = sqrt(L / 1745.0) * 100.0;
        nit = evaluate_nit(slider);
        nit_rounded = sprintf("%.3f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.3f", prev_nit + 0.005) + 0.0;
        }
        prev_nit = nit_rounded;
        printf "        <level> %4d    ,%4d    ,%7.3f    ,1.00 </level>\n", L, L, nit_rounded;
    }
    for (L = 1746; L <= 2047; L++) {
        ratio = (L - 1745.0) / (2047.0 - 1745.0);
        nit = prev_nit + (1100.0 - prev_nit) * ratio;
        nit_rounded = sprintf("%.3f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.3f", prev_nit + 0.005) + 0.0;
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
    chcon u:object_r:system_file:s0 "$TARGET_PD_XML"
    blog "APPLY" "P_D 标定写入成功 ($(wc -c < "$TARGET_PD_XML") 字节, $(grep -c '<level>' "$TARGET_PD_XML") 个 level)"
    _do_mount "P_D 次级配置" "$TARGET_PD_XML" "$ORIG_PD_XML"
else
    blog "APPLY" "警告: P_D 标定生成失败 (输出为空), 保留原文件不动"
fi

# 3. 写入 vendor display_id_*.xml (高通驱动电平三级联动)
DISP_SRC="$ORIG_DISP_XML"
if [ ! -f "$DISP_SRC" ]; then DISP_SRC="$TARGET_DISP_XML"; fi

# 结构嗅探: screenBrightnessMap 结构不同时原样保留并记录
if grep -q '<screenBrightnessMap interpolation="linear">' "$DISP_SRC" 2>/dev/null; then
    blog "APPLY" "面板配置结构嗅探: 匹配 linear screenBrightnessMap, 目标 $(basename "$ORIG_DISP_XML")"
else
    blog "APPLY" "警告: 面板配置结构与本模块预期不符, 将原样保留以防 vendor 显示服务异常"
fi

awk -v p0="$P_0" -v p30="$P_10" -v p60="550.0" -v p100="$P_8600" '
function evaluate_nit(slider,   t, smooth_t) {
    if (slider <= 0.0) return p0 + 0.0;
    if (slider <= 30.0) {
        t = slider / 30.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p0 + 0.0) + ((p30 + 0.0) - (p0 + 0.0)) * smooth_t;
    }
    if (slider <= 60.0) {
        t = (slider - 30.0) / 30.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p30 + 0.0) + ((p60 + 0.0) - (p30 + 0.0)) * smooth_t;
    }
    if (slider <= 100.0) {
        t = (slider - 60.0) / 40.0;
        smooth_t = t * t * (3.0 - 2.0 * t);
        return (p60 + 0.0) + ((p100 + 0.0) - (p60 + 0.0)) * smooth_t;
    }
    return p100 + 0.0;
}
BEGIN { in_map = 0 }
/<screenBrightnessMap interpolation="linear">/ {
    in_map = 1;
    print $0;
    prev_nit = 0.2000;
    for (i = 0; i <= 50; i++) {
        val = i / 50.0;
        slider = sqrt(val) * 100.0;
        nit = evaluate_nit(slider);
        nit_rounded = sprintf("%.4f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.4f", prev_nit + 0.0100) + 0.0;
        }
        prev_nit = nit_rounded;
        printf "    <point>\n      <value>%.4f</value>\n      <nits>%.4f</nits>\n    </point>\n", val, nit_rounded;
    }
    next;
}
in_map && /<\/screenBrightnessMap>/ {
    in_map = 0;
    print $0;
    next;
}
!in_map { print $0; }
' "$DISP_SRC" > "$TARGET_DISP_XML.tmp"

if [ -s "$TARGET_DISP_XML.tmp" ]; then
    cat "$TARGET_DISP_XML.tmp" > "$TARGET_DISP_XML"
    rm -f "$TARGET_DISP_XML.tmp"
    chmod 644 "$TARGET_DISP_XML"
    chcon u:object_r:vendor_configs_file:s0 "$TARGET_DISP_XML"
    blog "APPLY" "面板配置标定写入成功 ($(wc -c < "$TARGET_DISP_XML") 字节, $(grep -c '<nits>' "$TARGET_DISP_XML") 个采样点)"
    _do_mount "面板配置 ($(basename "$ORIG_DISP_XML"))" "$TARGET_DISP_XML" "$ORIG_DISP_XML"
else
    blog "APPLY" "警告: 面板配置标定生成失败 (输出为空), 保留原文件不动"
fi

# 4. 生成全量程 display_brightness_config_default.xml (级别数自适应设备原版,
#    将 30% 滑块锚定 P_10 Nit 与对应寄存器)
read_def_range
blog "APPLY" "default.xml 级别范围自适应: max=$DEF_MAX min=$DEF_MIN (读取自设备原版表头)"
awk -v p0="$P_0" -v p30="$P_10" -v p60="550.0" -v p100="$P_8600" \
    -v maxl="$DEF_MAX" -v minl="$DEF_MIN" '
function smoothstep(t) { return t * t * (3.0 - 2.0 * t); }
function evaluate_nit(slider,   t, st) {
    if (slider <= 0.0) return p0 + 0.0;
    if (slider <= 0.30) {
        t = slider / 0.30;
        st = smoothstep(t);
        return (p0 + 0.0) + ((p30 + 0.0) - (p0 + 0.0)) * st;
    }
    if (slider <= 0.60) {
        t = (slider - 0.30) / 0.30;
        st = smoothstep(t);
        return (p30 + 0.0) + ((p60 + 0.0) - (p30 + 0.0)) * st;
    }
    if (slider <= 1.00) {
        t = (slider - 0.60) / 0.40;
        st = smoothstep(t);
        return (p60 + 0.0) + ((p100 + 0.0) - (p60 + 0.0)) * st;
    }
    return p100 + 0.0;
}
function evaluate_hw(slider,   t, st) {
    if (slider <= 0.0) return 8;
    if (slider <= 0.30) {
        t = slider / 0.30;
        st = smoothstep(t);
        return int(8 + (1084 - 8) * st + 0.5);
    }
    if (slider <= 0.60) {
        t = (slider - 0.30) / 0.30;
        st = smoothstep(t);
        return int(1084 + (2400 - 1084) * st + 0.5);
    }
    if (slider <= 1.00) {
        t = (slider - 0.60) / 0.40;
        st = smoothstep(t);
        return int(2400 + (4095 - 2400) * st + 0.5);
    }
    return 4095;
}
BEGIN {
    printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n    <!-- calibrated by futureharmony for TB522FU ColorOS 16 -->\n    <version>20260911</version>\n    <lux_table_mode>3</lux_table_mode>\n    <hbm_lux_table_mode>3</hbm_lux_table_mode>\n    <brightness_table max=\"%d\" min=\"%d\">\n", maxl, minl;

    prev_nit = -1.0;
    for (L = 0; L <= maxl; L++) {
        if (L == 0) {
            nit = 0.0; hw = 0;
        } else if (L < minl) {
            ratio = L / (minl + 0.0);
            nit = ratio * (p0 + 0.0);
            hw = int(ratio * 8.0 + 0.5);
            if (hw < 1) hw = 1;
        } else {
            slider = (L - minl) / (maxl - minl);
            nit = evaluate_nit(slider);
            hw = evaluate_hw(slider);
        }
        nit_rounded = sprintf("%.3f", nit) + 0.0;
        if (nit_rounded <= prev_nit) {
            nit_rounded = sprintf("%.3f", prev_nit + 0.005) + 0.0;
        }
        prev_nit = nit_rounded;
        printf "        <level>%4d   ,%4d   ,%7.3f,1.00000</level>\n", L, hw, nit_rounded;
    }
    print "    </brightness_table>\n</root>";
}
' > "$TARGET_DEF_XML.tmp"

if [ -s "$TARGET_DEF_XML.tmp" ]; then
    cat "$TARGET_DEF_XML.tmp" > "$TARGET_DEF_XML"
    rm -f "$TARGET_DEF_XML.tmp"
    chmod 644 "$TARGET_DEF_XML"
    chcon u:object_r:system_file:s0 "$TARGET_DEF_XML"
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
settings put system screen_brightness "$ANCHOR_LVL"
settings put system screen_brightness_duration 0
blog "APPLY" "滑块学习缓存重置至 30% 基准 (Level $ANCHOR_LVL)"

blog_sync
echo "SUCCESS: 自动亮度联动映射已注入底层系统！"
echo "联动标定: 室内光(10Lux) -> 控制栏滑块(30%) -> 物理发光(${P_10}Nit)"
echo "单调安全: 全量程表 + 15 级环境光表严格双向递增，已彻底杜绝样条插值除零异常！"
