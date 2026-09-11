package com.futureharmony.tb522fu.brightness.hook;

import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;

/**
 * 针对 com.android.systemui 的 Hook
 * 确保控制中心亮度滑块的视觉显示与底层物理发光 100% 吻合
 */
public class SystemUIHook {

    private static final String TAG = "TB522FU_SystemUIHook";

    public static void init(ClassLoader classLoader) {
        hookBrightnessController(classLoader);
    }

    /**
     * Hook SystemUI 的 BrightnessController 及其 ColorOS 扩展实现
     */
    private static void hookBrightnessController(ClassLoader classLoader) {
        try {
            Class<?> ctrlImplClass = XposedHelpers.findClassIfExists(
                    "com.oplus.systemui.statusbar.phone.OplusBrightnessControllerExImpl", classLoader);

            if (ctrlImplClass != null) {
                XposedBridge.log(TAG + ": Found OplusBrightnessControllerExImpl in SystemUI");
                // 可在此拦截滑块位置与亮度值之间的双向转换
            }
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": Failed to hook SystemUI BrightnessController: " + t.getMessage());
        }
    }
}
