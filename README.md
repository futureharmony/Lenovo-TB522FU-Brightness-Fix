# Lenovo TB522FU 自动亮度优化模块 (Lenovo-TB522FU-Brightness-Fix)

[![Build & Release](https://github.com/futureharmony/Lenovo-TB522FU-Brightness-Fix/actions/workflows/release.yml/badge.svg)](https://github.com/futureharmony/Lenovo-TB522FU-Brightness-Fix/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/futureharmony/Lenovo-TB522FU-Brightness-Fix)](https://github.com/futureharmony/Lenovo-TB522FU-Brightness-Fix/releases/latest)

专为**联想拯救者 Y900 13英寸二代 (Lenovo TB522FU)** 移植 **ColorOS 16 (Android 16)** 打造的自动调光曲线与 10240 阶滑块重映射完整解决方案。

---

## 🌟 核心特性

1. **精准锚定 30% 黄金中枢**：
   * 修复移植后室内典型环境光下通知栏滑块卡在 10% 以下（~6%）的问题；
   * 将室内日常光照（10 ~ 12 Lux）精准映射为 **30% 滑块位置**，同时激发 **350 Nit** 充沛舒适发光（硬件背光寄存器 1084/4095）。
2. **全量程 10240 阶平滑自适应**：
   * 完美适配 ColorOS 16 的 `multibits_dimming_support` 机制；
   * 滑块在 0% ~ 100% 随环境光平滑动态过渡，杜绝突兀跳阶与断层。
3. **开机自愈看门狗（Bootloop Watchdog & Auto-Fallback）**：
   * 开机阶段植入异常监控标记，若系统发生连续 2 次启动异常未进入桌面，看门狗将立即触发自救熔断，自动禁用本模块并跳过所有挂载，彻底杜绝无限卡 Logo。
4. **交互式 WebUI 曲线调节工作台**：
   * 内置原生 WebUI 管理界面（支持 KernelSU / APatch / Magisk）；
   * 提供贝塞尔曲线 4 节点交互式拖拽画布，支持一键实时测试、套用与官方恢复；
   * 内置 1 秒高频动态遥测，实时读取环境光照度（Lux）、面板物理背光与滑块当前位置。
5. **SELinux 标签合规与沙盒隔离**：
   * 彻底解决 `webview_zygote` 沙盒访问被拒绝导致浏览器闪退的问题。
6. **刷入前环境与字节码机制嗅探（Pre-install Sanity & Dex Check）**：
   * 安装器在刷入写入前自动执行硬件面板、ColorOS 系统架构、核心服务包（`oplus-services.jar`）Dex 字节码特征（`OplusDisplaySplineManager`）以及系统目标配置完整性校验；
   * 若环境不匹配或缺少预定调光机制，立即安全熔断终止（Abort），一条文件都不写入，杜绝不知情用户误刷。

---

## 📁 项目工程结构

```
Lenovo-TB522FU-Brightness-Fix/
├── .github/workflows/release.yml   # GitHub Actions 自动编译与 Release 发布工作流
├── .gitignore                      # Git 忽略规则
├── PRINCIPLE.md                    # 详尽的修改原理与技术内幕深度文档
├── README.md                       # 本说明文档
├── build_zip.sh                    # 本地一键打包 Magisk / KernelSU 即刷包脚本
└── magisk_module/                  # KernelSU / APatch / Magisk 模块工程目录
    ├── module.prop                 # 模块元数据定义
    ├── customize.sh                # 刷入前环境嗅探与字节码机制拦截脚本
    ├── post-fs-data.sh             # 开机看门狗探测、SELinux 规整与 4 级联动 XML 挂载
    ├── service.sh                  # 开机平稳运行检测与看门狗解除机制
    ├── apply_curve.sh              # 10240 阶单调递增曲线计算与热套用引擎
    ├── get_telemetry.sh            # 30ms 毫秒级环境光/物理背光/滑块实时遥测接口
    ├── system.prop                 # 系统属性参数
    └── webroot/index.html          # 交互式曲线可视化拖拽调节 WebUI 页面
```

---

## 🚀 快速使用 (开箱即用)

### 下载与安装
1. 前往 **[GitHub Releases](https://github.com/futureharmony/Lenovo-TB522FU-Brightness-Fix/releases/latest)** 下载最新的模块刷机包：
   `Lenovo-TB522FU-Brightness-Fix-v*.zip`
2. 打开 **KernelSU / APatch / Magisk** 管理器；
3. 选择“从本地安装”刷入下载的 zip 文件并重启平板；
4. 开机后即刻生效！

### 使用 WebUI 交互式微调
1. 重启进入系统后，打开 KernelSU 管理器进入模块页面；
2. 点击本模块的 **WebUI** 按钮，即可打开控制台：
   * **实时数据微型条**：实时查看当前环境光（Lux）、物理背光阶数与滑块位置；
   * **交互式调光画布**：可自由拖动暗室、室内、明亮、户外 4 个关键锚点；
   * **一键套用 / 恢复**：支持临时测试、永久应用或一键恢复基准曲线。

---

## 📖 原理详解

深入了解 ColorOS 16 10240 阶标尺计算模型、样条插值除零数学机理以及开机看门狗架构，请参阅：
👉 [修改原理与技术内幕深度剖析 (PRINCIPLE.md)](./PRINCIPLE.md)

---

## 📄 License
MIT License
