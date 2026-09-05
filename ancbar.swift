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

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let bin = ancBinary()
    var busy = false
    var current: String?  // the CLI mode string, e.g. "on"

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "ANC")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        for (label, mode, _) in modes {
            let mi = NSMenuItem(title: label, action: #selector(pick(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode; menu.addItem(mi)
        }
        menu.addItem(.separator())
        let r = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"); q.target = self; menu.addItem(q)
        item.menu = menu
        refresh()  // seed the checkmark from the buds
    }

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
        // Map CLI stdout back to a mode key; unknown/failed clears the checkmark.
        current = output.flatMap { o in modes.first { $0.2 == o }?.1 }
        item.button?.toolTip = output.map { "ANC: \($0)" } ?? "ANC: unavailable"
        for mi in item.menu?.items ?? [] {
            if let m = mi.representedObject as? String { mi.state = (m == current) ? .on : .off }
        }
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard !busy, let mode = sender.representedObject as? String else { return }
        anc(mode) { self.apply($0 ?? self.current.map { c in modes.first { $0.1 == c }?.2 ?? "" }) }
    }
    @objc func refresh() { guard !busy else { return }; anc("status") { self.apply($0) } }
    @objc func quit() { NSApp.terminate(nil) }

    func validateMenuItem(_ mi: NSMenuItem) -> Bool { !busy }
}

let app = NSApplication.shared
let d = App(); app.delegate = d
app.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
app.run()
