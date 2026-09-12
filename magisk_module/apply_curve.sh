#!/system/bin/sh
# TB522FU 自动亮度三级联动标定脚本 (平板端本地运行)
# 核心指标: 室内 10 Lux -> 滑块 30% -> 实际发光 350 Nit
# 严格保证: 所有控制点双向严格单调递增，杜绝 OplusSpline NaN 除零异常

MODDIR="/data/adb/modules/tb522fu_brightness_fix"
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

case "$MODE" in
    "test")
        NIT=${2:-350}
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
        settings put system screen_brightness 3227
        echo "$HW_BL" > /sys/class/backlight/panel0-backlight/brightness
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
    mount -o bind "$TARGET_XML" "$ORIG_XML" 2>/dev/null
fi

# 2. 写入 display_brightness_config_P_D.xml (标定 2048 级: 严格递增)
PD_SRC="$ORIG_PD_XML"
if [ ! -f "$PD_SRC" ]; then PD_SRC="$TARGET_PD_XML"; fi

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
    mount -o bind "$TARGET_PD_XML" "$ORIG_PD_XML" 2>/dev/null
fi

# 3. 写入 vendor display_id_4630947077023927187.xml (高通驱动电平三级联动)
DISP_SRC="$ORIG_DISP_XML"
if [ ! -f "$DISP_SRC" ]; then DISP_SRC="$TARGET_DISP_XML"; fi

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
    mount -o bind "$TARGET_DISP_XML" "$ORIG_DISP_XML" 2>/dev/null
fi

# 4. 生成 10240 阶 display_brightness_config_default.xml (将 Level 3227/30% 滑块精准锚定 350 Nit 与 1084 寄存器)
awk -v p0="$P_0" -v p30="$P_10" -v p60="550.0" -v p100="$P_8600" '
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
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n    <!-- calibrated by futureharmony for TB522FU ColorOS 16 -->\n    <version>20260911</version>\n    <lux_table_mode>3</lux_table_mode>\n    <hbm_lux_table_mode>3</hbm_lux_table_mode>\n    <brightness_table max=\"10239\" min=\"222\">";

    prev_nit = -1.0;
    for (L = 0; L <= 10239; L++) {
        if (L == 0) {
            nit = 0.0; hw = 0;
        } else if (L < 222) {
            ratio = L / 222.0;
            nit = ratio * (p0 + 0.0);
            hw = int(ratio * 8.0 + 0.5);
            if (hw < 1) hw = 1;
        } else {
            slider = (L - 222.0) / 10017.0;
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
    mount -o bind "$TARGET_DEF_XML" "$ORIG_DEF_XML" 2>/dev/null
fi

# 同步 common 到 system_ext
cp -f "$TARGET_XML" "$MODDIR/system_ext/etc/display_brightness_config_common.xml" 2>/dev/null
mount -o bind "$TARGET_XML" "/system_ext/etc/display_brightness_config_common.xml" 2>/dev/null

# 重置异常拖动学习缓存至 30% 黄金基准 (Level 3227)
settings put system screen_brightness 3227
settings put system screen_brightness_duration 0

echo "SUCCESS: 自动亮度联动映射已注入底层系统！"
echo "联动标定: 室内光(10Lux) -> 控制栏滑块(30%) -> 物理发光(${P_10}Nit)"
echo "单调安全: 10240 阶全量程表 + 15 级环境光表严格双向递增，已彻底杜绝样条插值除零异常！"
