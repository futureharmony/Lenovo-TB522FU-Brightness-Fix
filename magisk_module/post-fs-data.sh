#!/system/bin/sh
MODDIR="${0%/*}"

# Set SELinux contexts
chcon -R u:object_r:system_file:s0 "$MODDIR/system" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/system_ext" 2>/dev/null
chcon -R u:object_r:system_file:s0 "$MODDIR/my_product" 2>/dev/null
chcon -R u:object_r:vendor_configs_file:s0 "$MODDIR/vendor" 2>/dev/null

# 1. Primary ColorOS brightness table (10240 levels)
TARGET_DEF="/system_ext/etc/display_brightness_config_default.xml"
SRC_DEF="$MODDIR/system_ext/etc/display_brightness_config_default.xml"
if [ -f "$SRC_DEF" ] && [ -f "$TARGET_DEF" ]; then
    mount -o bind "$SRC_DEF" "$TARGET_DEF"
fi

# 2. Ambient lux to Nit curve
TARGET_COMMON="/system/etc/display_brightness_config_common.xml"
SRC_COMMON="$MODDIR/system/etc/display_brightness_config_common.xml"
if [ -f "$SRC_COMMON" ] && [ -f "$TARGET_COMMON" ]; then
    mount -o bind "$SRC_COMMON" "$TARGET_COMMON"
fi

TARGET_EXT_COMMON="/system_ext/etc/display_brightness_config_common.xml"
if [ -f "$SRC_COMMON" ] && [ -e "$TARGET_EXT_COMMON" ]; then
    mount -o bind "$SRC_COMMON" "$TARGET_EXT_COMMON"
fi

# 3. Secondary P_D config
TARGET_PD="/my_product/vendor/etc/display_brightness_config_P_D.xml"
SRC_PD="$MODDIR/my_product/vendor/etc/display_brightness_config_P_D.xml"
if [ -f "$SRC_PD" ] && [ -f "$TARGET_PD" ]; then
    mount -o bind "$SRC_PD" "$TARGET_PD"
fi

# 4. Vendor display config
TARGET_DISP="/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
SRC_DISP="$MODDIR/vendor/etc/displayconfig/display_id_4630947077023927187.xml"
if [ -f "$SRC_DISP" ] && [ -f "$TARGET_DISP" ]; then
    mount -o bind "$SRC_DISP" "$TARGET_DISP"
fi
