"""Exercise recovery scheduling with a fake helper; never change real displays."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lidless-auto-test-") as directory:
    temporary = Path(directory)
    app = temporary / "RecoveryTests.app"
    macos = app / "Contents/MacOS"
    profiles = app / "Contents/Resources/EDID"
    macos.mkdir(parents=True)
    profiles.mkdir(parents=True)
    for name in ["P2710V_EDID_original.bin", "P2710V_EDID_max144.bin"]:
        (profiles / name).touch()
    (app / "Contents/Info.plist").write_text(
        '<plist version="1.0"><dict><key>CFBundleIdentifier</key>'
        '<string>cn.os-o.LidlessDisplay.RecoveryTests</string></dict></plist>'
    )
    helper = macos / "EDIDOverride"
    helper.write_text(
        '#!/bin/sh\ncd "$(dirname "$0")"\necho "$1" >> calls\n'
        'if [ -f fail ]; then exit 1; fi\nexit 0\n'
    )
    helper.chmod(0o755)
    source = (root / "LidlessDisplay.swift").read_text().split("\nlet displays = Displays()\n")[0]
    source += r'''
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
delegate.timer?.invalidate() // Drive time explicitly instead of waiting for the timer.
let domain = Bundle.main.bundleIdentifier!
UserDefaults.standard.removePersistentDomain(forName: domain)
defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
func settle() {
    let deadline = Date().addingTimeInterval(3)
    while delegate.edidProcess != nil && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    precondition(delegate.edidProcess == nil)
}
precondition(delegate.autoEDIDEnabled) // Default enabled; no inner-display switch.
precondition(!delegate.managed && delegate.pendingUntil == nil)
delegate.nextEDIDCheck = .distantPast
delegate.displaysSleeping()
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil)
delegate.displaysAwake()
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil) // Wait for wake stabilization.
delegate.nextEDIDCheck = .distantPast
delegate.pendingUntil = Date().addingTimeInterval(20)
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil)
delegate.pendingUntil = nil
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess != nil)
let first = delegate.edidProcess
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess === first) // Never overlap helpers.
settle()
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil) // Polling cooldown.
let folder = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
let calls = folder.appendingPathComponent("calls")
precondition(try! String(contentsOf: calls, encoding: .utf8) == "auto\n")
FileManager.default.createFile(atPath: folder.appendingPathComponent("fail").path, contents: nil)
delegate.nextEDIDCheck = .distantPast
delegate.checkAutomaticEDID()
settle()
precondition(delegate.autoEDIDFailed)
delegate.nextEDIDCheck = .distantPast
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil) // A write failure suspends retries.
delegate.displaysAwake()
precondition(!delegate.autoEDIDFailed)
delegate.toggleAutomaticEDID()
precondition(!delegate.autoEDIDEnabled)
delegate.nextEDIDCheck = .distantPast
delegate.checkAutomaticEDID()
precondition(delegate.edidProcess == nil)
print("PASS: startup, sleep/wake delay, confirmation guard, serialization, cooldown, failure suspension, toggle")
'''
    (temporary / "main.swift").write_text(source)
    subprocess.run(
        ["xcrun", "swiftc", "-module-cache-path", "/tmp/lidless-swift-cache",
         "-framework", "AppKit", "-framework", "CoreGraphics", "-framework", "IOKit",
         str(temporary / "main.swift"), "-o", str(macos / "RecoveryTests")],
        check=True,
    )
    subprocess.run([str(macos / "RecoveryTests")], check=True, timeout=20)
