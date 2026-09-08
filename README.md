# 开盖外屏 · LidlessDisplay

一个本地 macOS 菜单栏小工具：保持 MacBook 开盖，将内屏从桌面布局中断开，只使用外接显示器。不开启录音、不更改音频输入设备。

A small macOS menu bar app that disconnects the built-in display while keeping the MacBook lid open. Use external displays while retaining access to the built-in microphone. Written in Swift with no third-party dependencies.

## 解决什么问题？

这个项目源于一个实际的桌面办公需求：MacBook 连接两台外接显示器后，希望只使用这两块屏幕，同时继续使用笔记本自带的麦克风进行通话或语音输入。

合上笔记本盖子可以让桌面只保留外接显示器，但在这台 MacBook 上，合盖后内置麦克风也无法使用。保持开盖则能使用麦克风，却又多出一块不需要的内屏，鼠标和窗口仍可能进入这块屏幕。单纯把内屏亮度调到最低，也不能让它退出桌面布局。

LidlessDisplay 提供一个手动开关：**保持笔记本开盖，让内屏退出桌面布局，画面只输出到外接显示器。** 这样就能保留使用内置麦克风的条件，无需为了关闭内屏而合盖。

它适合使用一台或多台外接显示器、又希望继续使用笔记本内置麦克风的用户。工具只控制显示器，不接管麦克风；请在系统或通话应用中选择内置麦克风，并确认实际收音正常。

## 功能

- 手动断开或恢复内屏，支持多个外接显示器。
- 切换后须在 20 秒内确认，否则尝试恢复内屏。
- 外接屏全部断开时尝试恢复内屏，正常退出时恢复本工具关闭的内屏。
- 启动应用不会自动关闭内屏；不修改音频输入设备。
- 仅更改当前登录会话的显示配置，不调整 EDID、分辨率或刷新率。

## 使用

1. 双击 `build/LidlessDisplay.app`，在菜单栏找到笔记本箭头图标。
2. 保持笔记本开盖，并连接外接显示器。
3. 点击「仅用外接显示器」。画面可能短暂闪动。
4. 在 20 秒内重新打开菜单，点击「保留设置」；否则自动恢复内屏。
5. 随时点击「恢复内屏」。应用运行期间，全部外接屏断开会触发恢复尝试；正常退出也会恢复本工具关闭的内屏。

在系统设置 → 声音 → 输入选择「MacBook Pro 麦克风」。开盖避免合盖引起的麦克风硬件断开，应用本身不获取麦克风权限；收音效果需在目标通话/录音应用中实际确认。

## 构建与检查

需要 Apple Silicon Mac、macOS 26 或更新版本，以及包含 Swift 的 Xcode Command Line Tools。尚未验证其他机型和系统版本的兼容性。

```sh
git clone https://github.com/chengligen/LidlessDisplay.git
cd LidlessDisplay
zsh build.sh
open build/LidlessDisplay.app
```

构建生成 `build/LidlessDisplay.app` 和 `build/LidlessDisplay.zip`。应用使用本地临时签名，未经过 Apple 公证。

命令行检查与恢复：

```sh
build/LidlessDisplay.app/Contents/MacOS/LidlessDisplay --status
build/LidlessDisplay.app/Contents/MacOS/LidlessDisplay --restore
```

`--test` 在开盖且内屏启用时关闭内屏，等待 3 秒、读取音频设备列表，再恢复并检查状态。测试期间显示器会重新排列。

2026-09-08 在 M4 Pro / macOS 26.6.2、连接两台外接屏的配置下实测：内屏由 active=1 变为 0，两台外接屏持续 active=1，恢复后内屏回到 active=1。内屏断开期间系统仍列出「MacBook Pro 麦克风」。这只验证设备仍被识别，尚未完整测试实际录音、20 秒回退、拔线自动恢复及睡眠唤醒。

## 登录时启动

应用本身不自动注册登录启动项。可按需将应用加入 macOS 的登录项；启动时只显示菜单栏工具，「仅用外接显示器」仍需手动点击。配置后请保持应用所在路径不变。

## 限制与恢复

- 使用 macOS 私有 SkyLight 接口，系统升级后可能失效。仅提交当前会话配置，不写入永久显示配置，不调整 EDID、分辨率或刷新率。
- 睡眠或重新连接可能使系统恢复内屏；需要时再次手动切换。
- 自动恢复依赖应用仍在运行；强制结束或崩溃无法保证恢复。可重开应用点击「恢复内屏」，或运行上面的 `--restore`；也可拔掉外接屏、开合盖让系统重新检测。
- 切换显示器可能引起短暂黑屏、窗口重新排列或主屏变化。

接口资料：[ScreenTune](https://github.com/antonorlov/screen_tune)、[displaytoggle](https://github.com/calvincchan/displaytoggle)。

## 许可证

[MIT](LICENSE)
