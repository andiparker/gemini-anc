// Devialet Gemini II ANC control over BLE (Devialet GATT Audio service).
// Build: swiftc -O anc.swift -o anc      Usage: anc on|off|transparency|status
import CoreBluetooth
import Foundation

let svc = CBUUID(string: "0000D805-0000-0000-6465-7669616C6574")   // Audio
let chr = CBUUID(string: "0000DA03-0000-0000-6465-7669616C6574")   // CurrentAncConfiguration (uint8)
let modes: [String: UInt8] = ["on": 0, "off": 1, "transparency": 2] // Cancellation / Neutral / Transparency
let names = ["ANC on", "off", "transparency"]

let peerCache = NSHomeDirectory() + "/.anc-peer"  // cached peripheral UUID: skip the scan on later runs

final class ANC: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let want: UInt8?; var c: CBCentralManager!; var dev: CBPeripheral?; var scanning = false
    init(want: UInt8?) { self.want = want; super.init(); c = CBCentralManager(delegate: self, queue: nil) }
    func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { die("bluetooth not powered on (state \(c.state.rawValue))") }
        // Fast path: reconnect the last-known device directly, no ad-wait. Connect to an
        // already-active bud returns near-instantly; scan is only the cold/stale fallback.
        if let s = try? String(contentsOfFile: peerCache, encoding: .utf8),
           let id = UUID(uuidString: s.trimmingCharacters(in: .whitespacesAndNewlines)),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            dev = p; p.delegate = self; c.connect(p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {  // stale cache / out of range → scan fresh
                if p.state != .connected { c.cancelPeripheralConnection(p); self.dev = nil; self.scan() }
            }
        } else { scan() }
    }
    func scan() { guard !scanning else { return }; scanning = true; c.scanForPeripherals(withServices: nil) }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        // Devialet company id 0x0258 in manufacturer data; the buds don't advertise a name or service UUID.
        guard dev == nil, let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2, m[0] == 0x58, m[1] == 0x02 else { return }
        c.stopScan(); dev = p; p.delegate = self; c.connect(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        try? p.identifier.uuidString.write(toFile: peerCache, atomically: true, encoding: .utf8)
        p.discoverServices([svc])
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { die("connect failed: \(error.map { "\($0)" } ?? "")") }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { die("disconnected: \(error.map { "\($0)" } ?? "")") }
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        guard let s = p.services?.first else { die("audio service not found") }
        p.discoverCharacteristics([chr], for: s)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first else { die("anc characteristic not found") }
        guard let w = want else { return p.readValue(for: ch) }
        p.setNotifyValue(true, for: ch)  // buds apply the mode async; the notify carries the confirmed value
        p.writeValue(Data([w]), for: ch, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { die("write failed: \(e)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { p.readValue(for: ch) }  // fallback if no notify
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if let e = error { die("read failed: \(e)") }
        let v = ch.value?.first ?? 0xFF
        guard want == nil || v == want else { return }  // stale value, wait for the notify
        print(v < 3 ? names[Int(v)] : "unknown mode \(v)")
        c.cancelPeripheralConnection(p); exit(0)
    }
}

let arg = CommandLine.arguments.dropFirst().first ?? ""
if arg == "selftest" { assert(modes["on"] == 0 && modes["off"] == 1 && modes["transparency"] == 2 && names.count == 3); print("ok"); exit(0) }
guard arg == "status" || modes[arg] != nil else { print("usage: anc on|off|transparency|status"); exit(2) }
let anc = ANC(want: modes[arg])
RunLoop.main.run(until: Date().addingTimeInterval(15))
anc.die("timed out (earbuds not found or not responding)")
