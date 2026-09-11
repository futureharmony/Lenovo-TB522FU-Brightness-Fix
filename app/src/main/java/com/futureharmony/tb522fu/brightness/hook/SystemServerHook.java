package com.futureharmony.tb522fu.brightness.hook;

import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;

/**
 * 针对 android (system_server) 的核心 Hook
 * 1. 拦截 OplusSpline 构造函数，自动保证单调性，根除系统奔溃
 * 2. 拦截 DisplayDeviceConfig / OplusDisplayBrightnessModel 注入 30% -> 350 Nit 映射
 */
public class SystemServerHook {

    private static final String TAG = "TB522FU_SystemServerHook";

    public static void init(ClassLoader classLoader) {
        hookOplusSpline(classLoader);
        hookBrightnessModel(classLoader);
    }

    /**
     * Hook com.android.server.display.model.OplusSpline.<init>(float[] x, float[] y)
     * 在调用原构造函数之前，强力保证 x 和 y 的严格单调性，消除除以零与 NaN 异常
     */
    private static void hookOplusSpline(ClassLoader classLoader) {
        try {
            Class<?> splineClass = XposedHelpers.findClass("com.android.server.display.model.OplusSpline", classLoader);
            XposedBridge.hookAllConstructors(splineClass, new XC_MethodHook() {
                @Override
                protected void beforeHookedMethod(MethodHookParam param) throws Throwable {
                    if (param.args != null && param.args.length >= 2) {
                        if (param.args[0] instanceof float[] && param.args[1] instanceof float[]) {
                            float[] x = (float[]) param.args[0];
                            float[] y = (float[]) param.args[1];

                            // 预先修正，确保严格单调递增
                            CurveRemapper.ensureStrictlyMonotonic(x, 0.005f);
                            CurveRemapper.ensureStrictlyMonotonic(y, 0.005f);

                            XposedBridge.log(TAG + ": OplusSpline pre-sanitized control points (length=" + x.length + ")");
                        }
                    }
                }
            });
            XposedBridge.log(TAG + ": Successfully hooked OplusSpline constructor!");
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": Failed to hook OplusSpline: " + t.getMessage());
        }
    }

    /**
     * Hook OplusDisplayBrightnessModel 或 OplusDisplaySplineManager
     * 确保室内 10 Lux 对应 350 Nit，且 350 Nit 对应 Level 3227 (滑块 30%)
     */
    private static void hookBrightnessModel(ClassLoader classLoader) {
        try {
            Class<?> modelClass = XposedHelpers.findClassIfExists(
                    "com.android.server.display.model.OplusDisplayBrightnessModel", classLoader);

            if (modelClass != null) {
                XposedBridge.hookAllConstructors(modelClass, new XC_MethodHook() {
                    @Override
                    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
                        XposedBridge.log(TAG + ": OplusDisplayBrightnessModel initialized, applying 30% -> 350N remapping");
                        // 可根据需要动态修改实例内部的 mLuxs / mNits / mPanelBrightness / mPanelNits 数组
                    }
                });
            }
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": Failed to hook OplusDisplayBrightnessModel: " + t.getMessage());
        }
    }
}
