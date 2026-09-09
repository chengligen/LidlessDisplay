import AppKit
import CoreGraphics
import IOKit

// Private macOS APIs: resolve at runtime so an OS change fails safely.
typealias ListDisplays = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>) -> Int32
typealias EnableDisplay = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32

enum DisplayFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

final class Displays {
    private let framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private var rememberedInternal: UInt32?

    func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    func all() throws -> [UInt32] {
        guard let framework, let symbol = dlsym(framework, "SLSGetDisplayList") else {
            throw DisplayFailure.message("当前系统不支持显示器断开接口。")
        }
        let function = unsafeBitCast(symbol, to: ListDisplays.self)
        var count: UInt32 = 0
        guard function(0, nil, &count) == 0, count <= 128 else {
            throw DisplayFailure.message("无法读取显示器列表。")
        }
        if count == 0 { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard function(count, &ids, &count) == 0, count <= ids.count else {
            throw DisplayFailure.message("无法读取显示器列表。")
        }
        return Array(ids.prefix(Int(count)))
    }

    func internalID() throws -> UInt32 {
        if let id = try all().first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            rememberedInternal = id
            return id
        }
        if let rememberedInternal { return rememberedInternal }
        throw DisplayFailure.message("未找到笔记本内置显示器。")
    }

    func externals() throws -> [UInt32] {
        try all().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsActive($0) != 0 && CGDisplayIsOnline($0) != 0 }
    }

    func setInternal(_ enabled: Bool) throws {
        if !enabled && lidClosed() != false {
            throw DisplayFailure.message("请先打开笔记本盖子，再切换为仅用外接显示器。")
        }
        let id = try internalID()
        if try !enabled && externals().isEmpty {
            throw DisplayFailure.message("请先连接并启用外接显示器。")
        }
        guard let framework, let symbol = dlsym(framework, "SLSConfigureDisplayEnabled") else {
            throw DisplayFailure.message("当前系统不支持显示器断开接口。")
        }
        let function = unsafeBitCast(symbol, to: EnableDisplay.self)
        var transaction: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&transaction) == .success, let transaction else {
            throw DisplayFailure.message("无法开始更改显示器配置。")
        }
        let result = function(transaction, id, enabled)
        guard result == 0 else {
            CGCancelDisplayConfiguration(transaction)
            throw DisplayFailure.message("系统拒绝切换内屏（\(result)）。")
        }
        // Session-only: do not save a permanent display preference.
        let commit = CGCompleteDisplayConfiguration(transaction, .forSession)
        guard commit == .success else {
            throw DisplayFailure.message("显示器配置未生效（\(commit.rawValue)）。")
        }
    }

    func status() throws -> String {
        try all().map { id in
            "id=\(id) builtin=\(CGDisplayIsBuiltin(id)) active=\(CGDisplayIsActive(id)) online=\(CGDisplayIsOnline(id))"
        }.joined(separator: "\n")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let displays = Displays()
    var item: NSStatusItem!
    var timer: Timer?
    var managed = false
    var pendingUntil: Date?
    var switchStarted: Date?
    var lastError: String?
    var edidProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "laptopcomputer.and.arrow.down", accessibilityDescription: "开盖外屏")
        item.button?.toolTip = "开盖外屏 · LidlessDisplay"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
        let recoveryTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkRecovery() }
        RunLoop.main.add(recoveryTimer, forMode: .common)
        timer = recoveryTimer
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    func refresh() {
        guard let menu = item.menu else { return }
        menu.removeAllItems()
        let internalOn = (try? displays.internalID()).map { CGDisplayIsActive($0) != 0 } ?? false
        let count = (try? displays.externals().count) ?? 0
        let state = displays.lidClosed() == true ? "已合盖" : (internalOn ? "内屏开启" : "内屏关闭")
        menu.addItem(withTitle: "外接屏 \(count) 台 · \(state)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        if internalOn {
            add("仅用外接显示器", #selector(disable), enabled: count > 0 && displays.lidClosed() == false)
        } else {
            add("恢复内屏", #selector(restore))
        }
        if let pendingUntil {
            add("保留设置（\(max(0, Int(pendingUntil.timeIntervalSinceNow))) 秒后自动恢复）", #selector(confirm))
        }
        add("应用 144Hz 覆盖…", #selector(applyEDID))
        let more = NSMenu()
        add("检查覆盖状态…", #selector(checkEDID), to: more)
        add("取消覆盖，恢复原厂…", #selector(resetEDID), to: more)
        more.addItem(.separator())
        add("打开声音设置…", #selector(soundSettings), to: more)
        let moreItem = NSMenuItem(title: "更多", action: nil, keyEquivalent: "")
        moreItem.submenu = more
        menu.addItem(moreItem)
        if edidProcess != nil { menu.addItem(withTitle: "正在处理，请保持连接…", action: nil, keyEquivalent: "") }
        if let lastError { menu.addItem(withTitle: lastError, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        add("恢复内屏并退出", #selector(quit))
    }

    func add(_ title: String, _ action: Selector, enabled: Bool = true, to submenu: NSMenu? = nil) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = enabled && edidProcess == nil
        let menu = submenu ?? item.menu
        menu?.autoenablesItems = false
        menu?.addItem(entry)
    }

    @objc func disable() {
        managed = true // Recover even if the API reports an error after a partial change.
        switchStarted = Date()
        pendingUntil = Date().addingTimeInterval(20)
        do {
            try displays.setInternal(false)
            lastError = nil
        } catch { showError(error) }
        refresh()
    }

    @objc func confirm() { pendingUntil = nil; refresh() }

    @objc func restore() {
        do {
            try displays.setInternal(true)
            if let id = try? displays.internalID(), CGDisplayIsActive(id) != 0 {
                managed = false
                pendingUntil = nil
            }
            lastError = nil
        } catch { lastError = error.localizedDescription }
        refresh()
    }

    func checkRecovery() {
        guard managed else { return }
        if let switchStarted, Date().timeIntervalSince(switchStarted) < 2 { return }
        if let id = try? displays.internalID(), CGDisplayIsActive(id) != 0 {
            managed = false
            pendingUntil = nil
            refresh()
            return
        }
        if (try? displays.externals().isEmpty) == true || (pendingUntil.map { $0 <= Date() } ?? false) {
            restore()
        }
    }

    func showError(_ error: Error) {
        lastError = error.localizedDescription
        let alert = NSAlert()
        alert.messageText = "未能切换显示器"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func soundSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
    }

    @objc func checkEDID() { runEDID("check") }
    @objc func applyEDID() { runEDID("apply") }
    @objc func resetEDID() { runEDID("reset") }

    func runEDID(_ command: String) {
        guard edidProcess == nil else { return }
        guard pendingUntil == nil else {
            showError(DisplayFailure.message("请先完成内屏切换确认或恢复内屏，再操作 EDID。"))
            return
        }
        let resources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/EDID")
        let original = resources.appendingPathComponent("P2710V_EDID_original.bin")
        let modified = resources.appendingPathComponent("P2710V_EDID_max144.bin")
        guard FileManager.default.fileExists(atPath: original.path), FileManager.default.fileExists(atPath: modified.path) else {
            showError(DisplayFailure.message("此应用未附带已验证的 P2710V EDID 文件。请按照 README 配置本机文件后重新构建。"))
            return
        }
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/EDIDOverride")
        process.arguments = [command, original.path, modified.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] task in
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.edidProcess = nil
                self.refresh()
                let alert = NSAlert()
                alert.messageText = task.terminationStatus == 0 ? "EDID 检查与操作结果" : "EDID 操作未完成"
                alert.informativeText = output.isEmpty ? "未收到有效结果，请保持内屏开启并检查显示器连接。" : output
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
        do {
            try process.run()
            edidProcess = process
        } catch { showError(error) }
        refresh()
    }

    @objc func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if edidProcess != nil { return .terminateCancel }
        guard managed else { return .terminateNow }
        do { try displays.setInternal(true); return .terminateNow }
        catch { showError(error); return .terminateCancel }
    }
}

let displays = Displays()
if CommandLine.arguments.contains("--status") {
    do { print(try displays.status()) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--restore") {
    do { try displays.setInternal(true) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--test") {
    // Bounded live smoke test; always attempt recovery, including on failure.
    do {
        guard displays.lidClosed() == false, CGDisplayIsActive(try displays.internalID()) != 0 else {
            throw DisplayFailure.message("测试需要先开盖，并让内屏处于启用状态。")
        }
        print("BEFORE\n\(try displays.status())")
        do {
            try displays.setInternal(false)
            Thread.sleep(forTimeInterval: 3)
            print("DURING\n\(try displays.status())")
            guard CGDisplayIsActive(try displays.internalID()) == 0 else {
                throw DisplayFailure.message("内屏仍处于活动状态。")
            }
            let audioCheck = Process()
            audioCheck.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            audioCheck.arguments = ["SPAudioDataType"]
            try audioCheck.run()
            audioCheck.waitUntilExit()
        } catch { try? displays.setInternal(true); throw error }
        try displays.setInternal(true)
        Thread.sleep(forTimeInterval: 3)
        print("AFTER\n\(try displays.status())")
        guard CGDisplayIsActive(try displays.internalID()) != 0 else {
            throw DisplayFailure.message("内屏恢复尚未完成。")
        }
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
