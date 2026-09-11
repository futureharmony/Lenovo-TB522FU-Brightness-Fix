# TB522FU 自动亮度重映射插件 (LSPosed / Xposed 模块)

专为**联想小新 Pad Pro (Lenovo TB522FU)** 移植 **ColorOS 16 (Android 16)** 打造的自动调光曲线与 10240 阶滑块重映射增强插件。

---

## 🌟 核心特性

1. **精准锚定 30% 黄金中枢**：
   * 修复移植后室内环境光下通知栏滑块死死卡在 10% 以下（~6%）的问题；
   * 将室内典型日常光（10 ~ 12 Lux）精准映射为 **30% 滑块位置**，同时激发 **350 Nit** 充沛舒适发光（硬件背光寄存器 1084/4095）。
2. **全量程 10240 阶平滑自适应**：
   * 完美适配 ColorOS 16 的 `multibits_dimming_support` 机制；
   * 滑块在 0% ~ 100% 随环境光平滑动态过渡，杜绝突兀跳阶。
3. **免疫开机卡 Logo 保护机制**：
   * Hook 拦截 `OplusSpline` 构造过程，对控制点数组执行严格单调递增清洗（Strictly Monotonic Sanitize）；
   * 从 JVM 底层彻底根除反向样条（`mNitsToLuxSpline`）因相邻点相等除零导致 NaN 的 `IllegalArgumentException` 开机死锁崩溃。
4. **零物理侵入**：
   * 无需修改 System 分区镜像，随开随关，安全稳定。

---

## 📁 项目工程结构

```
TB522FU_Brightness_LSPosed/
├── .gitignore                      # Git 忽略规则
├── build.gradle                    # 顶层 Gradle 构建配置
├── settings.gradle                 # 仓库与子项目配置
├── gradle.properties               # JVM 与 AndroidX 配置
├── PRINCIPLE.md                    # 详尽的修改原理与技术内幕文档
├── README.md                       # 本说明文档
└── app/
    ├── build.gradle                # 模块编译依赖 (Xposed API 82)
    └── src/
        └── main/
            ├── AndroidManifest.xml # Xposed 模块元数据声明
            ├── assets/
            │   └── xposed_init     # Hook 入口引导文件
            ├── java/com/futureharmony/tb522fu/brightness/hook/
            │   ├── MainHook.java          # Zygote 与包加载分发中心
            │   ├── SystemServerHook.java  # 拦截 OplusSpline 与亮度映射
            │   ├── SystemUIHook.java      # 拦截控制中心滑块交互
            │   └── CurveRemapper.java     # 30%->350N 数学重映射引擎
            └── res/
                └── values/
                    └── strings.xml        # 模块名称与作用域定义
```

---

## 🛠️ 编译与安装指南

### 1. 编译构建
本项目为标准 Android Studio / Gradle 工程，直接在终端执行 Gradle 编译：
```bash
# 进入工程目录
cd TB522FU_Brightness_LSPosed

# 编译 Debug APK
./gradlew assembleDebug

# 或编译 Release APK
./gradlew assembleRelease
```
编译产物位于 `app/build/outputs/apk/debug/app-debug.apk`。

### 2. 安装与激活
1. 将编译好的 APK 推送安装至平板：
   ```bash
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```
2. 在平板上打开 **LSPosed Manager**：
   * 在模块列表中找到 **TB522FU 自动亮度重映射**；
   * 勾选启用该模块；
   * 确认推荐作用域已勾选 **系统框架 (android)** 与 **系统界面 (SystemUI)**；
3. 重启平板即可享受完美的自动亮度与滑块体验！

---

## 📖 原理详解

深入了解 ColorOS 16 10240 阶标尺计算模型、样条插值除零数学机理以及三级联动架构，请参阅：
👉 [修改原理与技术内幕深度剖析 (PRINCIPLE.md)](./PRINCIPLE.md)
