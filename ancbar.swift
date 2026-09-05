// Menu-bar front end for the `anc` CLI (Devialet Gemini II ANC control).
// Build: swiftc -O ancbar.swift -o ancbar    Run: ./ancbar   (lives in the menu bar)
// Finds the `anc` binary via $ANC_BIN, then next to this executable, then $PATH.
import AppKit

let modes = [("Noise Cancellation", "on", "ANC on"),
             ("Transparency", "transparency", "transparency"),
             ("Off (Neutral)", "off", "off")]

func ancBinary() -> String {
    if let e = ProcessInfo.processInfo.environment["ANC_BIN"], !e.isEmpty { return e }
    let sib = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("anc").path
    if FileManager.default.isExecutableFile(atPath: sib) { return sib }
    return "anc"  // fall back to PATH
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    var batteryItem: NSMenuItem!
    let bin = ancBinary()
    var busy = false
    var current: String?  // the CLI mode string, e.g. "on"

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "ANC")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.autoenablesItems = false  // keep the battery row full-strength; !busy guards prevent double-clicks
        for (label, mode, _) in modes {
            let mi = NSMenuItem(title: label, action: #selector(pick(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode; menu.addItem(mi)
        }
        menu.addItem(.separator())
        batteryItem = NSMenuItem(title: "", action: nil, keyEquivalent: ""); menu.addItem(batteryItem)
        setBattery("🔋  …")
        menu.addItem(.separator())
        let r = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        let a = NSMenuItem(title: "About ANC", action: #selector(about), keyEquivalent: ""); a.target = self; menu.addItem(a)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"); q.target = self; menu.addItem(q)
        menu.delegate = self
        item.menu = menu
        refresh()  // seed the checkmark from the buds
    }

    // Re-read whenever the menu opens so mode + battery are always current (values land ~2s later).
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    // Run `anc <arg>` off the main thread; deliver trimmed stdout (or nil on failure) back on main.
    func anc(_ arg: String, _ done: @escaping (String?) -> Void) {
        busy = true; item.button?.appearsDisabled = true
        DispatchQueue.global().async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: self.bin); p.arguments = [arg]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            let text: String?
            do {
                try p.run(); p.waitUntilExit()
                let d = out.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                text = p.terminationStatus == 0 ? s : nil
            } catch { text = nil }
            DispatchQueue.main.async { self.busy = false; self.item.button?.appearsDisabled = false; done(text) }
        }
    }

    func apply(_ output: String?) {
        // `status` prints the mode on line 1 and one battery line per device below it;
        // a mode write prints just the mode. Map line 1 to the checkmark either way.
        let lines = (output ?? "").split(separator: "\n").map(String.init)
        current = lines.first.flatMap { l in modes.first { $0.2 == l }?.1 }
        item.button?.toolTip = lines.first.map { "ANC: \($0)" } ?? "ANC: unavailable"
        for mi in item.menu?.items ?? [] {
            if let m = mi.representedObject as? String { mi.state = (m == current) ? .on : .off }
        }
        // Battery lines look like "left  34%"; collapse padding and show compactly. Only a status
        // read carries them — leave the last-known value in place after a plain mode write.
        let parts = lines.dropFirst().filter { !$0.hasPrefix("case") }  // buds only; case ruins the look
            .map { l -> String in
                let t = l.split(separator: " ").filter { !$0.isEmpty }
                let name = t.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""  // Left / Right
                return "\(name) \(t.count > 1 ? String(t[1]) : "")"
            }
        if !parts.isEmpty { setBattery("🔋  " + parts.joined(separator: "     ")) }
        else if output == nil { setBattery("🔋  unavailable") }  // fetch failed; don't leave a stale "…"
    }

    // Full-strength, slightly heavier text so the battery row reads clearly (a plain disabled item dims to grey).
    func setBattery(_ s: String) {
        batteryItem.attributedTitle = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor])
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard !busy, let mode = sender.representedObject as? String else { return }
        anc(mode) { self.apply($0 ?? self.current.map { c in modes.first { $0.1 == c }?.2 ?? "" }) }
    }
    @objc func refresh() { guard !busy else { return }; anc("status") { self.apply($0) } }
    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ANC",
            .applicationVersion: "1.0",
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
