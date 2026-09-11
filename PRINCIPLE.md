# 联想 TB522FU (ColorOS 16) 自动亮度重映射与工程化原理深度剖析

## 1. 硬件背景与问题起源

* **目标设备**：联想拯救者 Y900 13英寸二代 (Lenovo TB522FU)。
* **系统环境**：第三方移植适配的 **ColorOS 16 (Android 16)**。
* **屏幕特性**：大尺寸高刷新率面板，底层驱动支持 12-bit PWM 调光（硬件寄存器量程 `0 ~ 4095`），典型最大 SDR 亮度约为 **782 ~ 800 Nit**。

### 遇到的典型体验缺陷：
1. **暗光视觉停滞**：开机后室内环境下（光照约 10~12 Lux），实际显示发光尚可，但控制中心的亮度滑块视觉上卡在 **10% 以下（约 6%）**，且外界光照微调时，滑块几乎不动。
2. **目标与位置脱节**：当我们把目标发光提升至室内通透舒适的 **350 Nit** 时，控制中心滑块却直接跳到了 **60%** 位置，违背了“日常室内使用滑块居于 30%”的心理与人体工学预期。
3. **开机保护性崩溃**：在早期尝试修改曲线时，系统卡死在开机动画（BootAnimation），发生循环软重启（Bootloop）。

---

## 2. ColorOS 16 MultiBits 调光系统逆向分析

通过反编译 ColorOS 16 的 `SystemUI.apk`（`OplusBrightnessControllerExImpl`）及核心系统框架服务包 `oplus-services.jar`，摸清了其调光计算模型：

### 2.1 AOSP 原生标尺 vs ColorOS 10240 阶标尺
* **AOSP 标准**：通常使用基于浮点归一化（`0.0 ~ 1.0`）的平方根压缩模型：
  $$\text{Slider} = \sqrt{\text{BrightnessValue}} \times 100\%$$
* **ColorOS MultiBits 体系**：当检测到支持 `oplus.software.display.multibits_dimming_support` 特性时，系统自动切入 **10240 级标尺**：
  $$\text{MinLevel} = 222, \quad \text{MaxLevel} = 10239, \quad \text{Range} = 10017$$
  SystemUI 中的滑块视觉百分比不再经过平方根开方，而是**完全线性的相对位移**：
  $$\text{SliderPct} = \frac{\text{CurrentLevel} - 222}{10017} \times 100\%$$

### 2.2 核心亮度映射链路
ColorOS 内部的自动亮度经过了三层链式变换：
1. **环境光照度 (Lux) $\longrightarrow$ 目标显示亮度 (Nit)**：
   * 定义于 `display_brightness_config_common.xml` 中的 `<luxToNits>` 样条表。
2. **目标显示亮度 (Nit) $\longrightarrow$ 系统框架标尺等级 (Level 222 ~ 10240)**：
   * 定义于 `display_brightness_config_default.xml` 中的 `<nitsToLevels>` 映射表。
3. **系统框架标尺等级 (Level) $\longrightarrow$ 屏幕面板驱动背光 (PWM 0 ~ 4095)**：
   * 定义于 `display_id_4630947077023927187.xml` 中的底层面板配置。

---

## 3. “30% 滑块 激发 350 Nit” 的数学重映射模型

为了让室内日常环境光（10 ~ 12 Lux）下，通知栏滑块稳定在用户最习惯的 **30% 位置**，同时屏幕输出舒适充沛的 **350 Nit**，必须对两级样条曲线进行数学解耦与重定标：

### 3.1 目标参数计算
1. **滑块 30% 对应的 Framework Level**：
   $$\text{TargetLevel} = 222 + 30\% \times 10017 = 222 + 3005.1 = \mathbf{3227}$$
2. **一级曲线锚定（Lux ⟶ Nit）**：
   在 `display_brightness_config_common.xml` 中：
   * 将环境光 **10.0 Lux** 处的发光目标直接绑定为 **350.0 Nit**。
3. **二级曲线锚定（Nit ⟶ Level）**：
   在 `display_brightness_config_default.xml` 中：
   * 将发光目标 **350.0 Nit** 处映射的系统 Level 精准定标为 **3227**。
4. **底层硬件背光映射**：
   根据面板最大 800 Nit 对应 4095 阶 PWM 计算：
   $$\text{BacklightPWM} \approx 4095 \times \frac{350}{800}^{0.85} \approx \mathbf{1084} \quad (\sim 26.5\%)$$

---

## 4. 开机卡死 Logo 崩溃机理与数学除零陷阱

在早期的配置注入过程中，曾触发系统核心显示服务的致命异常导致死锁：
```java
FATAL EXCEPTION IN SYSTEM PROCESS: android.display
java.lang.IllegalArgumentException: The control points must have monotonic Y values.
	at com.android.server.display.model.OplusSpline.<init>(OplusSpline.java:79)
	at com.android.server.display.model.OplusDisplaySplineManager.createSplines(OplusDisplaySplineManager.java:124)
```

### 4.1 崩溃链条还原：
1. **双向样条插值（Bidirectional Spline）**：
   ColorOS 在 `OplusDisplaySplineManager.createSplines` 中，会同时构建两条样条曲线：
   * 正向曲线：`mLuxToNitsSpline = new OplusSpline(mLuxs, mNits)`
   * 反向曲线：`mNitsToLuxSpline = new OplusSpline(mNits, mLuxs)`（用于通过目标 Nit 反查环境光）
2. **除零生成 NaN**：
   在反向曲线中，`mNits` 成为自变量 $X$。如果前几个暗光锚点（如 0, 2, 4 Lux）的 Nit 值被设定为相同的保底值（如均为 `2.0 Nit`）：
   $$\Delta x = \text{nit}[i] - \text{nit}[i-1] = 2.0 - 2.0 = 0$$
   样条斜率 $m = \Delta y / \Delta x = \Delta y / 0 = \mathbf{NaN}$！
3. **单调性校验触发保护**：
   `OplusSpline` 构造器在校验时检测到斜率为 NaN 或非单调，立即抛出 `IllegalArgumentException`，直接拉崩 `system_server` 的核心显示线程。

### 4.2 解决方案：双向严格单调断言算法
所有控制点必须满足严格单调递增：
$$\forall i > 0, \quad x[i] - x[i-1] \ge \epsilon, \quad y[i] - y[i-1] \ge \epsilon \quad (\epsilon \ge 0.005)$$
且在写入 XML 文本之前，预先完成四舍五入后的严格大于判定，杜绝文本截断带来的等值重叠。

---

## 5. 开机看门狗自愈与容灾回退机制

为了彻底杜绝由于 ROM 版本微调或文件冲突导致的用户设备变砖或无限卡 Logo 风险，模块架构设计了三级自愈体系：

```
开机启动 (post-fs-data)
     │
     ├── 检查是否存在 disable 标记 ──(已禁用)──> 退出，纯净原厂开机
     │
     ├── 检查是否存在未清除的 .booting 标记
     │       ├── 存在 (上次开机未能正常进桌面) ──> 崩溃计数器 + 1
     │       │       └── 达到 2 次 ──> 触发熔断保护：写入 disable 标记并退出！
     │       └── 不存在 (首次正常开机) ──> 写入 .booting 标记
     │
     ├── 执行 SELinux 标签规整 (修复 webview_zygote FD 沙盒泄露)
     ├── 执行 4 级联动 bind 挂载
     │
系统桌面加载完毕 (service.sh)
     │
     └── 等待 sys.boot_completed == 1 并平稳运行 15 秒
             └── 清除 .booting 标记与崩溃计数器 (解除警报)
```

1. **第一级：配置生成单调性熔断**：
   `apply_curve.sh` 在计算 XML 控制点时内置单调性断言，出现任何 NaN 即刻终止，绝不写出损坏的配置文件。
2. **第二级：开机看门狗自动禁用（Bootloop Watchdog）**：
   连续 2 次无法顺利进入桌面，自动生成 `disable` 标记并跳过挂载，确保机器在下次开机时以 100% 官方纯净状态顺利开机。
3. **第三级：SELinux 标签合规**：
   全量执行 `u:object_r:system_file:s0` 上下文规整，杜绝 `webview_zygote` 沙盒因 `EACCES (-13)` 报 `Unable to stat FD 67` 崩溃。

---

## 6. 刷入前环境嗅探与字节码校验机制 (Pre-install Dex & Feature Check)

为了避免不知情用户在非移植版 ColorOS 或其他不兼容机型上盲目刷入导致异常，安装包通过 `customize.sh` 与 `update-binary` 部署了 4 道前置“防刷错拦截闸门”：

### 6.1 四重前置校验闸门
1. **硬件面板配置指纹校验**：
   * 检测 `/vendor/etc/displayconfig/display_id_4630947077023927187.xml` 是否存在。该文件严格绑定拯救者 Y900 13英寸二代（TB522FU）的屏幕控制器；若不存在立即终止安装。
2. **系统架构与系统指纹校验**：
   * 探测 `ro.build.version.oplusrom`、`ro.oplus.version.my_manifest` 以及 `/my_product` 挂载点，确保运行在真实的 ColorOS / Oplus 体系下。
3. **核心服务字节码深度嗅探（Dex Inspection 探针）**：
   * 系统在解包前，直接通过快速流式解压检查核心服务包：
     $$\text{unzip -p } \text{/system\_ext/framework/oplus-services.jar} \text{ classes*.dex} \mid \text{grep -Fq "OplusDisplaySplineManager"}$$
   * 探测 ColorOS 原生的自动亮度样条管理类 `OplusDisplaySplineManager` 与 `OplusSpline` 字节码符号。若 ROM 经过极度精简或更换为 AOSP 显示服务，安装器立即主动熔断（`abort`），一条模块文件都不会写入设备！
4. **目标挂载点完整性校验**：
   * 检查原厂 `/system_ext/etc/display_brightness_config_default.xml` 与 `/system/etc/display_brightness_config_common.xml` 是否齐全，确保 `mount -o bind` 目标点有效。
