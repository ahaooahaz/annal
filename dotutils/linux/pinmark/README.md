# Pinmark

一个为 Hyprland / Wayland 编写的轻量截图贴图工具。

**流程：框选屏幕区域 → 松开截图 → 截图原位悬浮 → 矩形/箭头标记 → 复制图片。**

## 功能

- 鼠标拖动框选区域，松开后截图，Esc 取消框选。
- 原位贴图，不参与平铺；不会改动 Hyprland 配置。
- 默认未选绘图工具，左键可以拖动贴图，工具栏跟随移动。
- 红色矩形框、红色箭头；再次点击已选工具可取消选中并恢复拖动。
- 右键撤销上一条标记，绘制过程中右键取消当前标记。
- 复制包含标记的 PNG；复制成功关闭当前这一张，其他已固定截图保留；最后一张关闭后程序退出。复制失败则保留原图。
- “另存为”按钮打开系统文件选择器，保存包含标记的 PNG；保存或取消后恢复贴图。
- 贴图有高对比度青色/深色边框，边框和工具栏不包含在复制或另存的图片中。
- 关闭按钮或 Esc 只关闭当前这一张；`--quit` 关闭所有贴图。
- 新增可切换图钉：亮起表示已固定，后续截图不再替换它；再次点击取消固定。
- 未固定的截图保持原有逻辑：下一次框选时暂时隐藏，新截图成功后被替换；取消或失败时恢复。
- 已固定的截图在后续框选和抓取时保持显示，位置、标记和各自的工具状态独立保留。
- 新选区若覆盖已固定的贴图，其画面和工具栏也会被截进去；可先拖开它或取消固定。
- 可同时保留多张已固定截图，并有一张默认未固定的新截图。

## 架构与依赖

Rust + Smithay Client Toolkit + tiny-skia，直接使用 Wayland layer-shell、viewporter 和共享内存绘制。

- 不依赖 Python、GTK 或 Qt。
- `slurp` 负责框选；`grim` 负责单次截图；`wl-copy` 负责剪贴板。
- 另存为通过 Rust D-Bus 客户端调用你已有的 `xdg-desktop-portal` 文件选择器；不依赖 zenity/kdialog。
- 文件对话框打开时暂时隐藏正在另存的这一张，其他贴图不受影响。取消或保存后恢复该图。
- 同目录临时文件写入后原子替换，只保存用户在对话框确认的文件位置。
- 没有常驻抓屏、动画循环或联网逻辑。只有交互变化时才重新绘制，绘制按合成器帧回调节流。
- PNG 复制合成与编码在工作线程执行，普通截图使用 RGB 和快速压缩。
- 图像不自动保存到磁盘。复制后，你已有的剪贴板历史工具可能会保留图片。

支持 layer-shell v4、viewporter 和 wlroots screencopy 的 Wayland 会话；目标环境是 Arch Linux + Hyprland。GNOME/X11 不适用。

### Arch 运行依赖（由你自行安装）

```bash
sudo pacman -S --needed grim slurp wl-clipboard
```

另存为还需要已有的 `xdg-desktop-portal` 和适配桌面的 FileChooser 后端（常见为 GTK 或 KDE 后端）。用 `--check` 检查；程序不会自动安装或改变 Portal 配置。

## 手动编译与启动

源码位于 `~/.annal/dotutils/linux/pinmark/`。需要 Rust 1.89 或更新版本；安装与编译均由你手动操作，本目录不附带预编译程序。

```bash
cd ~/.annal/dotutils/linux/pinmark
cargo build --release --locked
./target/release/pinmark --check
./target/release/pinmark
```

工具栏图标从左到右：**矩形 → 箭头 → 复制 → 另存为（软盘）→ 图钉 → 关闭**。

未选工具时左键拖动；选中矩形/箭头后左键绘制，再次点击该工具取消选中。图钉按钮亮起时，截图会跨后续截图操作保留；再点一次恢复临时截图状态。复制或关闭只影响当前图片，其他已固定截图保留；最后一张关闭时退出程序。另存为完成后保留该图。

### 不读取屏幕的演示模式

```bash
./target/release/pinmark --demo
```

它只显示程序生成的棋盘格测试图，可验证原位覆盖、矩形、箭头与复制，不抓取你的屏幕。

### 关闭全部贴图

```bash
./target/release/pinmark --quit
```

## 从源码构建

需要 Rust 1.89 或更新版本，以及常规构建工具。使用当前 Arch 稳定 Rust 最省事。

```bash
cargo build --release --locked
./target/release/pinmark --check
./target/release/pinmark
```

`--check` 只检查运行依赖、用户私有运行目录、Wayland 协议和 Portal 文件选择器，不截图、不修改配置。

macOS 可运行核心单元测试，但不能启动 Wayland 界面：

```bash
cargo test --all-targets
```

### 安装与卸载（暂不启用）

本目录的 Makefile 仅提供空的 `install`、`uninstall` 目标。运行它们或默认 `make` 都不会编译、下载、安装、创建链接或修改配置：

```bash
make install    # 什么都不做
make uninstall  # 什么都不做
```

本目录位于 `dotutils/linux/pinmark/`，仓库扫描时能够发现它，但 `install` 和 `uninstall` 仍为空操作。`packaging/` 中的旧打包示例仅作为源码资料保留，本次不使用它。

## 快捷键说明

目前的 Hyprland F1 调用 `~/.local/bin/pinmark`。本项目的 `make install` 是空操作，所以 Cargo 编译完成后，需由你按原来的手动方式更新该入口；否则 F1 仍可能运行旧版本。建议先直接运行新编译的 `target/release/pinmark` 验证图钉功能。

这次不改动你的任何快捷键。

由于贴图属于 layer-shell 覆盖层而非普通窗口，你当前 `Super+C` 的 Hyprland 全局转发逻辑可能不会把按键发给贴图。第一版直接使用工具栏的“复制”按钮，避免改动现有配置。

## 限制

- 暂不支持一次跨越多个显示器的选区；这类选区会被拒绝，而不会生成错位/裁切的贴图。
- 贴图可在截图所在的显示器内拖动；暂不支持跨屏拖动、缩放、文字、OCR 或其他画笔。
- 贴图跨工作区可见；它位于 overlay 层，但锁屏仍由合成器保护。
- 工具栏优先放在截图之外；全屏截图时可能叠在截图的一角，导出的 PNG 不包含它。
- 当前面向普通 SDR 截图，未做专门 HDR/ICC 色彩管理适配。
- 每张已固定截图都会保留自己的图像与标记，内存开销随截图数量和像素尺寸增长。
- 图像内存与选区像素尺寸成正比；不能把大幅截图当作零内存开销。

## 测试

```bash
cargo fmt --check
cargo test --all-targets
cargo clippy --all-targets -- -D warnings
cargo run --release --example render_bench
```

覆盖固定/取消固定、仅替换临时截图、多图独立关闭和稳定 ID、区域解析、负坐标、矩形/箭头几何、工具取消选中、拖动与边缘约束、PNG 分辨率和透明度、预览边框不污染导出、64 字节对齐共享缓冲区、另存的 URI/原子写入、私有 socket、单实例、子进程超时、剪贴板后台进程 EOF 等。

`render_bench` 使用生成的图片，不读取屏幕或修改剪贴板。其结果不是你机器上的端到端截图耗时。

## 文件

- `src/ui.rs`：原生 Wayland 覆盖层与多图交互。
- `src/pins.rs`：固定状态、稳定图像 ID 和替换/关闭规则。
- `src/geometry.rs`：区域、矩形、箭头和标注状态。
- `src/render.rs`：图像绘制、工具栏和 PNG 导出。
- `src/save.rs`：Portal 另存为、取消请求和原子文件写入。
- `src/backend.rs`：框选、截图、复制与子进程管理。
- `src/ipc.rs`：用户私有 socket 与单实例控制。
- `src/cli.rs`：命令行和只读运行检查。

本地 socket 位于 `$XDG_RUNTIME_DIR/pinmark.sock`，权限 0600。运行目录必须由当前用户拥有且权限为 0700。不创建系统服务。

## 致谢

使用 [Smithay Client Toolkit](https://github.com/Smithay/client-toolkit)、[tiny-skia](https://github.com/linebender/tiny-skia)、[grim](https://gitlab.freedesktop.org/emersion/grim)、[slurp](https://github.com/emersion/slurp) 和 [wl-clipboard](https://github.com/bugaevc/wl-clipboard)。第三方依赖遵循各自许可证。
