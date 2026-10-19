# LidlessDisplay

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

A small macOS menu bar app that disconnects the built-in display while keeping the MacBook lid open, so you can use only external displays. It does not record audio or change the audio input device.

Written in Swift with no third-party dependencies. These language options apply to the documentation only; the app currently has a Simplified Chinese interface.

## What problem does it solve?

This project started with a desk setup: a MacBook connected to two external monitors. The goal was to use only those monitors while continuing to use the built-in microphone for calls or voice input.

Closing the lid removed the built-in display from the desktop, but on the MacBook used for this project, it also made the built-in microphone unavailable. Keeping the lid open preserved microphone access, but left an unwanted screen that could still contain windows and receive the pointer. Lowering its brightness to zero did not remove it from the desktop layout.

LidlessDisplay provides a manual switch: **keep the lid open and remove the built-in display from the desktop layout, leaving only external displays.** This preserves the conditions needed to use the built-in microphone without closing the lid to disable the screen.

It is intended for users with one or more external monitors who want to keep using the built-in microphone. The app controls displays, not the microphone. Select the built-in microphone in system or calling-app settings and verify that audio is actually captured.

## Features

- Manually disconnect or restore the built-in display, with support for multiple external monitors.
- Apply, inspect, or cancel a temporary 144Hz EDID override for the validated P2710V profile.
- Confirm the display change within 20 seconds, or the app attempts to restore the built-in display.
- Attempt to restore the built-in display when all external monitors disconnect; restore a display disabled by this app when quitting normally.
- Launching the app does not automatically disable the built-in display or change audio input devices.
- The built-in display switch changes only the current login session's display configuration. The 144Hz EDID override supports automatic recovery.

## P2710V dual-monitor detection workaround

In the tested M4 Pro setup with two P2710V monitors, macOS sometimes detected only one external monitor. Applying a temporary EDID capped at 144Hz to one monitor restored dual-monitor operation. The underlying cause remains unconfirmed, and the override has been lost before, so the app provides a manual reapply action.

The main menu contains the built-in display switch, Apply 144Hz override (`应用 144Hz 覆盖…`), and Quit. The display switch shows either Use external displays only (`仅用外接显示器`) or Restore built-in display (`恢复内屏`). Check override status (`检查覆盖状态…`), Cancel override and restore factory EDID (`取消覆盖，恢复原厂…`), and sound settings are under More (`更多`). **Launching the app does not disable the built-in display automatically.** Automatic 144Hz recovery (`更多 → 自动恢复 144Hz`) is enabled by default. It checks about 3 seconds after launch or screen wake, then every 15 seconds. It skips an existing override and reapplies a lost override only to one fully byte-matched target, including with two external monitors connected and the built-in display off. Checks pause during sleep. Write/verification failures suspend retries until the next wake or manual re-enabling; missing or ambiguous targets are skipped and checked later. Automatic checks do not open dialogs. Canceling the override disables automatic recovery; successfully applying it manually enables recovery again. Quitting does not cancel the EDID override, to avoid disrupting a working dual-monitor connection.

To manually apply or cancel the override (automatic recovery does not require this single-monitor setup):

1. Keep the MacBook lid open and the built-in display active. If the app disconnected it, select Restore built-in display first.
2. Connect only the target P2710V whose EDID was previously validated and backed up. Disconnect the other external monitor's video cable.
3. Select the operation and wait for readback verification. Reconnect the second monitor afterward.

This feature supports **only one specific validated P2710V EDID**, not every monitor of the same model. The helper checks both file hashes, a full byte-for-byte match against the connected monitor's EDID, and that exactly one target matches. It refuses mismatches. It uses `IOAVServiceSetVirtualEDIDMode` for a runtime software override and does not flash monitor firmware. If verification fails, it attempts to restore the previous state and reports whether rollback was verified.

The public repository does not include the local monitor's EDID data. To use this feature, create the Git-ignored `EDID/` directory at the project root, place these two **previously validated files** there, and rebuild:

- `P2710V_EDID_original.bin`, SHA-256: `be791d6ffbe772e6464bc5346e7f0f93e2e794dff72c6f7ced148278bd892b03`
- `P2710V_EDID_max144.bin`, SHA-256: `39bc876b9062f9951ca373ba76ca6163097a7f9fc85b7c08e1f9a2d566376e56`

A local build embeds these files in the app, so distributing that app or ZIP also distributes the data. Without the files, you can still build and use the built-in display switch; EDID operations report missing configuration. Do not rename another monitor's files and try to use them as these profiles.

## Usage

1. Open `build/LidlessDisplay.app` and find the laptop-with-arrow icon in the menu bar.
2. Keep the lid open and connect your external monitors.
3. Select Use external displays only (`仅用外接显示器`). The displays may briefly flicker.
4. Reopen the menu within 20 seconds and select Keep settings (`保留设置`); otherwise the app attempts to restore the built-in display.
5. Select Restore built-in display (`恢复内屏`) whenever needed. While the app is running, disconnecting all external monitors triggers a recovery attempt. Normal quitting also restores a display disabled by this app.

In System Settings → Sound → Input, select MacBook Pro Microphone. Keeping the lid open avoids the microphone's lid-close hardware disconnect. The app does not request microphone permission; verify actual audio capture in your calling or recording app.

## Build and checks

Requires an Apple Silicon Mac, macOS 26 or later, and Xcode Command Line Tools with Swift. Compatibility with other hardware and OS versions has not been verified.

```sh
git clone https://github.com/chengligen/LidlessDisplay.git
cd LidlessDisplay
zsh build.sh
open build/LidlessDisplay.app
```

The build produces `build/LidlessDisplay.app` and `build/LidlessDisplay.zip`. The app is locally ad-hoc signed and is not notarized by Apple.

Command-line inspection and recovery:

```sh
build/LidlessDisplay.app/Contents/MacOS/LidlessDisplay --status
build/LidlessDisplay.app/Contents/MacOS/LidlessDisplay --restore
```

With the lid open and built-in display active, `--test` disables that display, waits 3 seconds, lists audio devices, then restores the display and checks its state. Displays are rearranged during this test.

On 2026-09-08, testing on an M4 Pro running macOS 26.6.2 with two external monitors showed the built-in display changing from active=1 to 0, both externals remaining active=1, and the built-in returning to active=1 after restoration. MacBook Pro Microphone remained listed while the display was disconnected. This verifies device enumeration only. Actual recording, the 20-second rollback, cable-disconnect recovery, and sleep/wake behavior have not been fully tested.

## Launch at login

The app does not register itself as a login item. You can optionally add it to macOS Login Items. At launch, it only shows the menu bar tool; Use external displays only still requires a manual click. Keep the app at the same path after configuring this.

## Limitations and recovery

- Uses private SkyLight / IOKit APIs that may stop working after macOS updates. The built-in display switch changes the session configuration; EDID override changes the modes reported to macOS without writing to monitor hardware.
- Sleep or reconnection may restore the built-in display. Switch it off manually again if needed.
- Automatic recovery depends on the app continuing to run; force-quitting or crashes do not guarantee restoration. Reopen the app and select Restore built-in display, or run `--restore`. Disconnecting external monitors and closing/reopening the lid may also prompt system detection.
- Display changes may cause brief black screens, window rearrangement, or a change of primary display.

Display API references: [ScreenTune](https://github.com/antonorlov/screen_tune), [displaytoggle](https://github.com/calvincchan/displaytoggle).

EDID API reference: [mac-edid-override](https://github.com/kdotc2/mac-edid-override). Version 1.1 has passed build and signature verification, current override readback, and rejection checks for damaged/mismatched files and two connected external monitors. End-to-end testing of apply/cancel and failure rollback in the new app still requires a single target monitor setup; applying the override with the earlier standalone helper succeeded.

Version 1.2 recovery was tested on M4 Pro / macOS 27.0.1 on 2026-10-19: after deliberately clearing the target override, the running app restored it in about 2 seconds, verified readback, and kept both external displays active. The original built-in-display-off state was then restored. Scheduling tests with a fake helper cover startup, sleep/wake delay, serialization, cooldown, failure suspension, and the toggle (`python3 tests/test_automatic_edid.py`, requires a macOS graphical session). Long-term behavior after real display power-off, sleep, and cable reconnection still needs everyday validation.

## License

[MIT](LICENSE)
