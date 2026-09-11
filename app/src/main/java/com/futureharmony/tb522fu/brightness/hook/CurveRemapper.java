package com.futureharmony.tb522fu.brightness.hook;

/**
 * 联想 TB522FU ColorOS 16 亮度标尺重映射核心算法
 * 核心指标: 室内 10 Lux -> 滑块 30% -> 物理发光 350 Nit
 */
public class CurveRemapper {

    public static final int LEVEL_MIN = 222;
    public static final int LEVEL_MAX = 10239;
    public static final int LEVEL_RANGE = LEVEL_MAX - LEVEL_MIN; // 10017
    public static final int LEVEL_TARGET_30 = 3227; // 222 + 10017 * 0.30

    public static final float NIT_MIN = 2.0f;
    public static final float NIT_TARGET_30 = 350.0f;
    public static final float NIT_60 = 550.0f;
    public static final float NIT_MAX = 782.0f;

    public static final int HW_MIN = 8;
    public static final int HW_TARGET_30 = 1084;
    public static final int HW_60 = 2400;
    public static final int HW_MAX = 4095;

    public static float smoothstep(float t) {
        return t * t * (3.0f - 2.0f * t);
    }

    /**
     * 根据控制中心滑块比例 (0.0 ~ 1.0) 计算目标 Nit 亮度
     */
    public static float evaluateNit(float slider) {
        if (slider <= 0.0f) return NIT_MIN;
        if (slider <= 0.30f) {
            float t = slider / 0.30f;
            return NIT_MIN + (NIT_TARGET_30 - NIT_MIN) * smoothstep(t);
        }
        if (slider <= 0.60f) {
            float t = (slider - 0.30f) / 0.30f;
            return NIT_TARGET_30 + (NIT_60 - NIT_TARGET_30) * smoothstep(t);
        }
        if (slider <= 1.00f) {
            float t = (slider - 0.60f) / 0.40f;
            return NIT_60 + (NIT_MAX - NIT_60) * smoothstep(t);
        }
        return NIT_MAX;
    }

    /**
     * 根据控制中心滑块比例 (0.0 ~ 1.0) 计算硬件背光寄存器值 (0 ~ 4095)
     */
    public static int evaluateHw(float slider) {
        if (slider <= 0.0f) return HW_MIN;
        if (slider <= 0.30f) {
            float t = slider / 0.30f;
            return Math.round(HW_MIN + (HW_TARGET_30 - HW_MIN) * smoothstep(t));
        }
        if (slider <= 0.60f) {
            float t = (slider - 0.30f) / 0.30f;
            return Math.round(HW_TARGET_30 + (HW_60 - HW_TARGET_30) * smoothstep(t));
        }
        if (slider <= 1.00f) {
            float t = (slider - 0.60f) / 0.40f;
            return Math.round(HW_60 + (HW_MAX - HW_60) * smoothstep(t));
        }
        return HW_MAX;
    }

    /**
     * 保证浮点数数组严格单调递增，防止反向样条插值除零和 NaN
     */
    public static void ensureStrictlyMonotonic(float[] arr, float minStep) {
        if (arr == null || arr.length <= 1) return;
        for (int i = 1; i < arr.length; i++) {
            if (arr[i] <= arr[i - 1]) {
                arr[i] = arr[i - 1] + minStep;
            }
        }
    }
}
