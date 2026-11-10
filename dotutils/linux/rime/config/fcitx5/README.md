# Fcitx5 鼠须管主题

`themes/squirrel`（浅色）和 `themes/squirrel-dark`（深色）参照
`../squirrel.custom.yaml` 的**当前生效样式**：横排候选、JetBrainsMono Nerd Font、
18 pt 候选字体、约 12 pt 序号字体、4 px 圆角、紧凑间距、左右约 8 px 留白及半透明背景。
鼠须管未指定 `color_scheme`，实际使用 macOS 系统配色；配置中未启用的 Bamboo
不是这两个主题的配色来源。这里近似复现系统浅色／深色颜色，不修改 Mac 配置。

## 安装

在另一台 Linux 机器的仓库根目录执行：

```sh
make -C dotutils/linux/rime install
```

安装会沿用统一的备份／软链接规则，创建以下链接（支持自定义 XDG 路径）：

| 安装位置 | 仓库来源 |
| --- | --- |
| `$XDG_DATA_HOME/fcitx5/rime` | `plugins/rime-ice` |
| `$XDG_DATA_HOME/fcitx5/themes/squirrel` | `config/fcitx5/themes/squirrel` |
| `$XDG_DATA_HOME/fcitx5/themes/squirrel-dark` | `config/fcitx5/themes/squirrel-dark` |
| `$XDG_CONFIG_HOME/fcitx5/conf/classicui.conf` | `config/fcitx5/conf/classicui.conf` |
| `$XDG_CONFIG_HOME/fcitx5/conf/rime.conf` | `config/fcitx5/conf/rime.conf` |

`XDG_DATA_HOME` 默认 `~/.local/share`，`XDG_CONFIG_HOME` 默认 `~/.config`。
现有同名配置和主题先备份为 `.backup.时间戳`；其他主题和配置不受影响。
`uninstall` 将这些链接移为备份，`prune` 仅清理登记目标的备份。
macOS 安装仍只链接 `~/Library/Rime` 和共用 Rime 配置，不安装 Fcitx5 文件。

安装前请退出 Fcitx5，避免它保存旧配置覆盖链接；安装后重新启动 Fcitx5，
并从 Rime 菜单执行「重新部署」。确保已安装 `fcitx5-rime`、经典用户界面组件、
JetBrainsMono Nerd Font 和中文字体（如 Noto Sans CJK SC）。

`classicui.conf` 自动启用浅色主题，并在支持系统颜色模式检测的 Fcitx5／桌面上
跟随系统切换深色；关闭系统强调色覆盖，以保持这里定义的颜色。
若自动切换不可用，可在经典用户界面设置中手动选择 `squirrel-dark`。
`rime.conf` 使用 `PreeditMode=ComposingText`，对应鼠须管的内嵌预编辑；
应用不支持内嵌预编辑时会回退到候选框显示。

**注意：经典用户界面主题、横排和字体设置影响所有使用该界面的输入法，
不只 Rime。** 安装会替换整个 `classicui.conf` 和 `rime.conf`，而非合并；
如需保留个人选项，请参考备份补充到对应的仓库文件中。
Fcitx5 配置工具可能以原子写入的方式替换软链接；修改后可再次 `make install`
恢复链接，但应先把希望保留的设置同步到仓库文件。

## 与鼠须管的差异及维护

- Fcitx5 不读取 `squirrel.custom.yaml`；这是一份对应配置，**不是自动转换或同步**。
  修改 Mac 样式后，请相应更新这里的配置／SVG。
- `Font` 在 `conf/classicui.conf`；`LabelTextSizeFactor=67` 将序号缩到约 12 pt，
  `CommentTextSizeFactor=100` 保持注释与候选字号一致。
  这些独立字号／颜色选项需要支持它们的新版本 Fcitx5；旧版本忽略不支持的键，
  序号和注释会回退到该版本默认样式。
- 圆角由 16×16 SVG 加 4 px 九宫格切片实现；调整圆角时应同时修改 SVG 的 `rx`
  和对应的 `Background/Margin`、`Highlight/Margin`。
  使用图片时 Fcitx5 忽略对应的 `Color`，更改颜色需同时更新 SVG 和备用 `Color`。
- Fcitx5 不支持鼠须管的 `candidate_format` 模板，但 fcitx5-rime 的默认序号
  已经不带句点；序号后空格及注释前空格由前端生成，不能精确替换为窄空格。
- 透明度为约 93%；macOS 原生毛玻璃、Display P3 色彩、分数像素边距、字体回退
  和 DPI 缩放不能跨平台完全一致。Linux 背景透明还依赖合成器；这里不要求 KWin 模糊。
- 深色跟随依赖桌面向 Fcitx5 提供颜色模式信号，不会仅凭应用窗口颜色判断。

## 安装规则测试

```sh
make -C dotutils/linux/rime test
```

测试使用临时 HOME／XDG 目录和本地插件夹具，不访问网络或修改真实输入法配置。
