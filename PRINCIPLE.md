# 联想 TB522FU (ColorOS 16) 自动亮度重映射与工程化原理深度剖析

## 1. 硬件背景与问题起源

* **目标设备**：联想小新 Pad Pro (Lenovo TB522FU)，搭载高通骁龙旗舰芯片 (SM8750)。
* **系统环境**：第三方移植适配的 **ColorOS 16 (Android 16)**。
* **屏幕特性**：高刷新率 LCD/OLED 面板，硬件背光驱动支持 12-bit PWM 调光（寄存器范围 `0 ~ 4095`），典型最大 SDR 亮度约为 **782 ~ 800 Nit**。

### 遇到的典型体验缺陷：
1. **暗光视觉停滞**：开机后室内环境下（光照约 10~12 Lux），实际显示发光尚可，但控制中心的亮度滑块视觉上卡在 **10% 以下（约 6%）**，且外界光照变化时，滑块几乎不动。
2. **目标与位置脱节**：当我们把目标发光提升至室内通透舒适的 **350 Nit** 时，控制中心滑块却直接跳到了 **60%** 位置，违背了“日常使用滑块居于 30%”的心理与人体工学预期。
3. **开机保护性崩溃**：在尝试通过 XML 修改曲线时，开机多次卡死在 BootAnimation 动画，系统循环软重启。

---

## 2. ColorOS 16 MultiBits 调光系统逆向分析

通过反编译 ColorOS 16 的 `SystemUI.apk`（`OplusBrightnessControllerExImpl`）及核心服务包 `oplus-services.jar`，摸清了其调光计算模型：

### 2.1 AOSP 原生标尺 vs ColorOS 10240 阶标尺
* **AOSP 标准**：通常使用基于浮点归一化（`0.0 ~ 1.0`）的平方根压缩模型：
  $$\text{Slider} = \sqrt{\text{BrightnessValue}} \times 100\%$$
* **ColorOS MultiBits 体系**：当检测到支持 `oplus.software.display.multibits_dimming_support` 特性时，系统自动切入 **10240 级标尺**：
  $$\text{MinLevel} = 222, \quad \text{MaxLevel} = 10239, \quad \text{Range} = 10017$$
  SystemUI 中的滑块视觉百分比不再经过平方根开方，而是**完全线性的相对位移**：
  $$\text{SliderPosition} = \frac{\text{CurrentLevel} - 222}{10239 - 222} = \frac{\text{CurrentLevel} - 222}{10017}$$

### 2.2 视觉卡在 10% 以下的数学根因
在原生未调校的 ROM 中，室内 10 Lux 分配给系统的内部级别只有 **830**：
$$\text{SliderPosition} = \frac{830 - 222}{10017} = \frac{608}{10017} = \mathbf{6.07\%}$$
此时外界光线在 5~15 Lux 之间波动时，Level 变动量不足 50 阶，在 3840 像素屏幕上的位移不到 2 个物理像素，导致用户直观感觉“滑块坏了，永远卡在 10% 以下不动”。

---

## 3. 三级联动架构与 30% 黄金中枢标定

为了实现 **室内日常 (10 Lux) $\longrightarrow$ 控制中心滑块 (30%) $\longrightarrow$ 舒适发光 (350 Nit)**，必须重构整套联动链条：

```
[环境光传感器 (Lux)]
        │  (查阅 common.xml 的 lux_table)
        ▼
[目标屏幕发光 (Nit)] ──── 10 Lux 对应 350.0 Nit
        │  (查阅 default.xml 的 brightness_table)
        ▼
[内部阶数 (Level)] ────── 350 Nit 映射至 Level 3227 ───► 滑块计算: (3227-222)/10017 = 30.0%
        │
        ▼
[硬件背光寄存器 (HW)] ──── 映射至 hw = 1084 (满量程 4095) ───► 面板物理激发 350 Nit
```

### 核心标定锚点表：
* **0% 滑块 (Level 222)**：0 Lux 暗室底限 $\leftrightarrow$ 2.0 Nit $\leftrightarrow$ hw = 8
* **30% 滑块 (Level 3227)**：**10 Lux 室内黄金中枢 $\leftrightarrow$ 350.0 Nit $\leftrightarrow$ hw = 1084**
* **60% 滑块 (Level 6232)**：50 Lux 明亮办公 $\leftrightarrow$ 550.0 Nit $\leftrightarrow$ hw = 2400
* **100% 滑块 (Level 10239)**：8600 Lux 户外顶格 $\leftrightarrow$ 782.0 Nit $\leftrightarrow$ hw = 4095

---

## 4. 开机卡死 Logo 崩溃机理与数学除零陷阱

在通过配置注入曲线时，曾触发致命异常导致系统无限重启：
```java
FATAL EXCEPTION IN SYSTEM PROCESS: android.display
java.lang.IllegalArgumentException: The control points must have monotonic Y values.
	at com.android.server.display.model.OplusSpline.<init>(OplusSpline.java:79)
	at com.android.server.display.model.OplusDisplaySplineManager.createSplines(OplusDisplaySplineManager.java:124)
```

### 逆向还原崩溃链条：
1. **双向样条插值（Bidirectional Spline）**：
   ColorOS 在 `OplusDisplaySplineManager.createSplines` 中，会同时构建两条曲线：
   * 正向曲线：`mLuxToNitsSpline = new OplusSpline(mLuxs, mNits)`
   * 反向曲线：`mNitsToLuxSpline = new OplusSpline(mNits, mLuxs)`（用于通过目标 Nit 反查环境光）
2. **除零生成 NaN**：
   在反向曲线中，`mNits` 成为自变量 $X$。如果前几个暗光锚点（如 0, 2, 4 Lux）的 Nit 值被设定为相同的保底值（如均为 `2.0 Nit`）：
   $$\Delta x = \text{nit}[i] - \text{nit}[i-1] = 2.0 - 2.0 = 0$$
   样条斜率 $m = \Delta y / \Delta x = \Delta y / 0 = \mathbf{NaN}$！
3. **单调性校验触发保护**：
   `OplusSpline` 构造器在校验时检测到斜率为 NaN 或非单调，立即抛出 `IllegalArgumentException`，直接拉崩 `system_server` 的核心显示线程。

### 解决方案：双向严格单调与精度进位算法
所有控制点必须满足：
$$\forall i > 0, \quad x[i] - x[i-1] \ge \epsilon, \quad y[i] - y[i-1] \ge \epsilon \quad (\epsilon \ge 0.005)$$
且在写入 XML 文本之前，必须预先完成四舍五入后的严格大于判定，杜绝文本截断带来的等值重叠。

---

## 5. LSPosed 模块工程化设计优势

相比于单纯依赖 Magisk 静态挂载 XML，使用 **LSPosed (Xposed)** 进行动态 Hook 拥有不可替代的优势：

1. **运行时免疫崩溃**：
   通过 Hook `OplusSpline.<init>(float[] x, float[] y)`，在构造函数执行前直接在 JVM 内存中对控制点数组执行快速单调修正（`ensureStrictlyMonotonic`）。即使系统文件出现异常配置，也不会发生闪退开机卡死。
2. **无需重启即时生效**：
   无需每次修改 XML 都执行长达数十秒的系统完整重启，Hook 拦截层可在用户在 WebUI 调整滑动条时即刻动态重算并热生效。
3. **无侵入性**：
   完全不触动 `/system` 或 `/system_ext` 物理分区文件，不影响 OTA 升级和 SafetyNet/Play Integrity 验证。
