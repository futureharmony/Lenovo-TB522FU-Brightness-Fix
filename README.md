# Lenovo TB522FU 自动亮度修复套件 (Lenovo-TB522FU-Brightness-Fix)

专为**联想小新 Pad Pro (Lenovo TB522FU)** 移植 **ColorOS 16 (Android 16)** 打造的自动调光曲线与 10240 阶滑块重映射完整解决方案。

---

## 🌟 核心特性

1. **精准锚定 30% 黄金中枢**：
   * 修复移植后室内环境光下通知栏滑块卡在 10% 以下（~6%）的问题；
   * 将室内典型日常光（10 ~ 12 Lux）精准映射为 **30% 滑块位置**，同时激发 **350 Nit** 充沛舒适发光（硬件背光寄存器 1084/4095）。
2. **全量程 10240 阶平滑自适应**：
   * 完美适配 ColorOS 16 的 `multibits_dimming_support` 机制；
   * 滑块在 0% ~ 100% 随环境光平滑动态过渡，杜绝突兀跳阶。
3. **免疫开机卡 Logo 保护机制**：
   * 彻底根除 ColorOS 16 反向样条（`mNitsToLuxSpline`）因相邻点相等除零导致 NaN 的 `IllegalArgumentException` 开机死锁崩溃。
4. **双重实现方案**：
   * **方案 A：KernelSU / Magisk 模块**：带可视化交互式贝塞尔曲线 WebUI，支持拖拽调控与高频毫秒级环境光遥测。
   * **方案 B：LSPosed Hook 插件**：零文件篡改，直接在内存层拦截并清洗 `OplusSpline` 样条控制点。

---

## 📁 项目工程结构

```
Lenovo-TB522FU-Brightness-Fix/
├── .gitignore                      # Git 忽略规则
├── build.gradle                    # 顶层 Gradle 构建配置
├── settings.gradle                 # 仓库与子项目配置
├── gradle.properties               # JVM 与 AndroidX 配置
├── PRINCIPLE.md                    # 详尽的修改原理与技术内幕深度文档
├── README.md                       # 本说明文档
├── app/                            # 【方案 B】LSPosed 插件 Android Studio 源码工程
│   ├── build.gradle                # 模块编译依赖 (Xposed API 82)
│   └── src/main/
│       ├── AndroidManifest.xml     # Xposed 模块元数据声明
│       ├── assets/xposed_init      # Hook 入口引导文件
│       └── java/com/futureharmony/tb522fu/brightness/hook/
│           ├── MainHook.java          # Zygote 与包加载分发中心
│           ├── SystemServerHook.java  # 拦截 OplusSpline 与亮度映射
│           ├── SystemUIHook.java      # 拦截控制中心滑块交互
│           └── CurveRemapper.java     # 30%->350N 数学重映射引擎
└── magisk_module/                  # 【方案 A】KernelSU / Magisk 即刷即用模块
    ├── module.prop                 # 模块信息
    ├── post-fs-data.sh             # 4 级联动 XML 动态挂载
    ├── service.sh                  # 后台遥测与系统优化服务
    ├── apply_curve.sh              # 底层 10240 阶曲线重算与注入引擎
    ├── get_telemetry.sh            # 30ms 毫秒级环境光/背光/滑块实时遥测接口
    └── webroot/index.html          # 交互式曲线可视化拖拽调节 WebUI
```

---

## 🛠️ 使用指南

### 方案 A：KernelSU / Magisk 模块（推荐，即刷即用）
1. 将 `magisk_module/` 打包为 zip，或直接推送到平板 `/data/adb/modules/tb522fu_brightness_fix`；
2. 在 KernelSU / APatch / Magisk 中启用该模块并重启；
3. 打开 KernelSU Manager 中的 WebUI 界面，即可在屏幕上直观拖拽自定义曲线、查看 1 秒高频实时环境光（Lux）与硬件背光。

### 方案 B：LSPosed 插件编译与安装
1. 本项目为标准 Android Studio / Gradle 工程，直接在终端执行编译：
   ```bash
   ./gradlew assembleDebug
   ```
2. 推送安装 APK：
   ```bash
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```
3. 在 LSPosed 中启用，勾选 **系统框架 (android)** 与 **系统界面 (SystemUI)**，重启平板生效。

---

## 📖 原理详解

深入了解 ColorOS 16 10240 阶标尺计算模型、样条插值除零数学机理以及三级联动架构，请参阅：
👉 [修改原理与技术内幕深度剖析 (PRINCIPLE.md)](./PRINCIPLE.md)
