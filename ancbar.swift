// Menu-bar front end for the `anc` CLI (Devialet Gemini II ANC control).
// Build: swiftc -O ancbar.swift -o ancbar    Run: ./ancbar   (lives in the menu bar)
import AppKit
import ServiceManagement

let modes = [("Noise Cancellation", "on", "ANC on"),
             ("Transparency", "transparency", "transparency"),
             ("Off (Neutral)", "off", "off")]
let modeIcon = ["on": "waveform.slash", "transparency": "ear", "off": "headphones"]  // current mode at a glance
let lowBattery = 20  // percent threshold for the ⚠️ warning

func ancBinary() -> String {
    // $ANC_BIN override, else the `anc` sibling next to this executable (the bundled case).
    // No $PATH search: Process would resolve a bare name relative to cwd, not PATH, so return the
    // sibling path even if absent — Process then fails cleanly rather than doing a surprising cwd lookup.
    if let e = ProcessInfo.processInfo.environment["ANC_BIN"], !e.isEmpty { return e }
    return URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("anc").path
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    var batteryItem: NSMenuItem!
    var loginItem: NSMenuItem!
    let bin = ancBinary()
    var busy = false
    var pending: String?      // a mode clicked while busy, run when the current op finishes
    var current: String?      // the CLI mode string, e.g. "on"

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("headphones", dim: true)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (label, mode, _) in modes {
            let mi = NSMenuItem(title: label, action: #selector(pick(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode; menu.addItem(mi)
        }
        menu.addItem(.separator())
        batteryItem = NSMenuItem(title: "", action: nil, keyEquivalent: ""); menu.addItem(batteryItem)
        setBattery("🔋  …")
        menu.addItem(.separator())
        let r = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: ""); loginItem.target = self; menu.addItem(loginItem)
        let a = NSMenuItem(title: "About ANC", action: #selector(about), keyEquivalent: ""); a.target = self; menu.addItem(a)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"); q.target = self; menu.addItem(q)
        menu.delegate = self
        item.menu = menu
        updateLoginState()
        refresh()  // seed mode + battery from the buds
    }

    func menuWillOpen(_ menu: NSMenu) { updateLoginState(); refresh() }

    // Run `anc <arg>` off the main thread; deliver (stdout, humanError) back on main. Exactly one is non-nil.
    func anc(_ arg: String, _ done: @escaping (String?, String?) -> Void) {
        busy = true; item.button?.appearsDisabled = true
        DispatchQueue.global().async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: self.bin); p.arguments = [arg]
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            var stdout = "", stderr = "", ok = false
            do {
                try p.run()
                // `anc` output is a few short lines, so draining both pipes before waitUntilExit is safe.
                stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit(); ok = p.terminationStatus == 0
            } catch { stderr = "\(error)" }
            DispatchQueue.main.async {
                self.busy = false
                if ok { done(stdout.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
                else  { done(nil, self.humanError(stderr)) }
                if let pm = self.pending { self.pending = nil; self.performMode(pm) }  // run a queued click
            }
        }
    }

    // Map the CLI's stderr to one actionable line for the menu.
    func humanError(_ stderr: String) -> String {
        let e = stderr.lowercased()
        if e.contains("permission") || e.contains("privacy") { return "Bluetooth access needed (System Settings)" }
        if e.contains("bluetooth is off") { return "Bluetooth is off" }
        if e.contains("not supported") { return "Bluetooth not supported" }
        if e.contains("timed out") || e.contains("not found") || e.contains("disconnected") || e.contains("no readable") || e.contains("connect failed") { return "Earbuds not found — take them out of the case" }
        return "Unavailable"
    }

    func performMode(_ mode: String) {
        setBattery("⋯  Switching…")
        anc(mode) { out, err in
            if let out = out { self.apply(out) } else { self.showError(err) }
        }
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        if busy { pending = mode; setBattery("⋯  Switching…"); return }  // queue instead of silently dropping
        performMode(mode)
    }
    @objc func refresh() {
        guard !busy else { return }
        anc("status") { out, err in
            if let out = out { self.apply(out) } else { self.showError(err) }
        }
    }

    func apply(_ output: String) {
        // `status` prints the mode on line 1 and one battery line per device below it; a mode write
        // prints just the mode. Line 1 drives the checkmark + icon either way.
        let lines = output.split(separator: "\n").map(String.init)
        current = lines.first.flatMap { l in modes.first { $0.2 == l }?.1 }
        item.button?.toolTip = lines.first.map { "ANC: \($0)" } ?? "ANC: unknown"
        for mi in item.menu?.items ?? [] {
            if let m = mi.representedObject as? String { mi.state = (m == current) ? .on : .off }
        }
        setIcon(current.flatMap { modeIcon[$0] } ?? "headphones", dim: current == nil)
        // Battery lines like "left  34%" → "Left 34%", ⚠️ when low. Only status carries them;
        // leave the last value after a plain mode write.
        let parts = lines.dropFirst().filter { !$0.hasPrefix("case") }.map { l -> String in
            let t = l.split(separator: " ").filter { !$0.isEmpty }
            let name = t.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
            let pctStr = t.count > 1 ? String(t[1]) : ""
            let warn = (Int(pctStr.filter(\.isNumber)) ?? 100) < lowBattery ? "⚠️ " : ""
            return "\(warn)\(name) \(pctStr)"
        }
        if !parts.isEmpty { setBattery("🔋  " + parts.joined(separator: "     ")) }
    }

    // A failed op must never look like success: show the reason, do not flip the checkmark.
    func showError(_ msg: String?) {
        item.button?.toolTip = "ANC: \(msg ?? "Unavailable")"
        setBattery("⚠︎  \(msg ?? "Unavailable")")
        setIcon("headphones", dim: true)
    }

    func setBattery(_ s: String) {
        batteryItem.attributedTitle = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor])
    }
    func setIcon(_ symbol: String, dim: Bool) {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ANC") {
            img.isTemplate = true; item.button?.image = img
        }
        item.button?.appearsDisabled = dim || busy
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }  // e.g. running the bare binary rather than the installed .app
        updateLoginState()
    }
    func updateLoginState() { loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off }

    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ANC",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            .credits: NSAttributedString(string: "Devialet Gemini II noise-cancellation control"),
            .init(rawValue: "Copyright"): "© 2026 Andi Parker",
        ])
    }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let d = App(); app.delegate = d
app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
app.run()
