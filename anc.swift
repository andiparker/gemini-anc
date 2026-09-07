// Devialet Gemini II ANC control over BLE (Devialet GATT Audio service).
// Build: swiftc -O anc.swift -o anc      Usage: anc on|off|transparency|status
// `status` also reports per-bud + case battery levels.
import CoreBluetooth
import Foundation

let svc = CBUUID(string: "0000D805-0000-0000-6465-7669616C6574")   // Audio
let chr = CBUUID(string: "0000DA03-0000-0000-6465-7669616C6574")   // CurrentAncConfiguration (uint8)
let modes: [String: UInt8] = ["on": 0, "off": 1, "transparency": 2] // Cancellation / Neutral / Transparency
let names = ["ANC on", "off", "transparency"]

// Each device (two buds + case) exposes a standard Battery Level (0x2A19) in its own Devialet service.
let batChr = CBUUID(string: "2A19")
let batSvcs: [(uuid: CBUUID, label: String)] = [
    (CBUUID(string: "0000D801-0000-0000-6465-7669616C6574"), "left"),
    (CBUUID(string: "0000D802-0000-0000-6465-7669616C6574"), "right"),
    (CBUUID(string: "0000D803-0000-0000-6465-7669616C6574"), "case"),
]

let peerCache = NSHomeDirectory() + "/.anc-peer"  // cached peripheral UUID: skip the scan on later runs
let timeout: TimeInterval = 20  // ponytail: cold start (buds waking from case) can be slow; raise if it still clips
let minRSSI = -70               // ponytail: proximity floor (dBm) to avoid a stranger's buds; tune per environment
let pickWindow: TimeInterval = 1.5  // collect advertisers this long before choosing, so the nearest can win

// Cold-scan device selection (pure, so it's unit-testable): a lone Devialet is yours; when several are
// in range, require one above the proximity floor and take the strongest (your own buds are closest).
func chooseCandidate(_ cs: [(id: UUID, rssi: Int)], floor: Int) -> UUID? {
    if cs.count == 1 { return cs.first?.id }
    return cs.filter { $0.rssi >= floor }.max(by: { $0.rssi < $1.rssi })?.id
}

final class ANC: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let want: UInt8?; var c: CBCentralManager!; var dev: CBPeripheral?; var scanning = false; var cachePath = false; var done = false
    var candidates: [UUID: (p: CBPeripheral, rssi: Int)] = [:]  // cold-scan advertisers, best RSSI per device
    var expected = 0; var received = 0; var mode: UInt8?; var bat: [CBUUID: UInt8] = [:]  // status reads
    init(want: UInt8?) { self.want = want; super.init(); c = CBCentralManager(delegate: self, queue: nil) }
    func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOff:    die("Bluetooth is off")
        case .unauthorized:  die("Bluetooth permission denied — grant access in System Settings > Privacy & Security > Bluetooth")
        case .unsupported:   die("Bluetooth LE not supported on this Mac")
        case .resetting, .unknown: return  // transient — wait for the next state update (the timeout guards us)
        case .poweredOn: break
        @unknown default: return
        }
        // Fast path: reconnect the last-known device directly, no ad-wait. Connect to an
        // already-active bud returns near-instantly; scan is only the cold/stale fallback.
        if let s = try? String(contentsOfFile: peerCache, encoding: .utf8),
           let id = UUID(uuidString: s.trimmingCharacters(in: .whitespacesAndNewlines)),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            cachePath = true; dev = p; p.delegate = self; c.connect(p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {  // stale cache / out of range → scan fresh
                if self.cachePath, p.state != .connected { self.rescanOrDie("timed out reconnecting to the cached device") }
            }
        } else { scan() }
    }
    func scan() {
        guard !scanning else { return }; scanning = true
        c.scanForPeripherals(withServices: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + pickWindow) { self.pickNearest() }
    }
    // Choose from the advertisers collected so far; if none qualifies yet, wait and re-check (timeout caps it).
    func pickNearest() {
        guard dev == nil else { return }
        let list = candidates.map { (id: $0.key, rssi: $0.value.rssi) }
        if let id = chooseCandidate(list, floor: minRSSI), let cand = candidates[id] {
            c.stopScan(); dev = cand.p; cand.p.delegate = self; c.connect(cand.p)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.pickNearest() }
        }
    }

    // A cached peripheral can be gone or be a different device with no Devialet audio service. Rather than
    // fail, drop it and fall back to a fresh scan — but only once (a real scan failing then does die).
    func rescanOrDie(_ msg: String) {
        guard cachePath, !scanning else { die(msg) }
        cachePath = false
        if let d = dev { c.cancelPeripheralConnection(d) }
        dev = nil; expected = 0; received = 0; mode = nil; bat = [:]; candidates = [:]
        scan()
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        // Devialet company id 0x0258 in manufacturer data; the buds don't advertise a name or service UUID.
        guard dev == nil, let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2, m[0] == 0x58, m[1] == 0x02 else { return }
        let r = rssi.intValue
        guard r != 127 else { return }  // 127 = RSSI unavailable
        candidates[p.identifier] = (p, max(candidates[p.identifier]?.rssi ?? Int.min, r))  // collect; pickNearest decides
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        if (try? p.identifier.uuidString.write(toFile: peerCache, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: peerCache)
        }
        p.discoverServices(want != nil ? [svc] : [svc] + batSvcs.map { $0.uuid })
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { rescanOrDie("connect failed: \(error.map { "\($0)" } ?? "")") }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard !done else { return }  // our own post-success teardown, ignore
        rescanOrDie("disconnected: \(error.map { "\($0)" } ?? "")")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        if let e = e { return rescanOrDie("service discovery failed: \(e)") }
        if want != nil {  // write path: just the ANC characteristic
            guard let s = p.services?.first(where: { $0.uuid == svc }) else { return rescanOrDie("audio service not found") }
            return p.discoverCharacteristics([chr], for: s)
        }
        // status path: ANC mode + one battery read per present service. expected fixed up front so a
        // fast first read can't make us print before the rest arrive.
        let found = p.services ?? []
        expected = found.filter { s in s.uuid == svc || batSvcs.contains { $0.uuid == s.uuid } }.count
        guard expected > 0 else { return rescanOrDie("no readable services found") }
        for s in found {
            if s.uuid == svc { p.discoverCharacteristics([chr], for: s) }
            else if batSvcs.contains(where: { $0.uuid == s.uuid }) { p.discoverCharacteristics([batChr], for: s) }
        }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        if want != nil {  // write path
            guard let ch = s.characteristics?.first else { return rescanOrDie("anc characteristic not found") }
            return p.writeValue(Data([want!]), for: ch, type: .withResponse)
        }
        // status path: a missing/errored characteristic counts as a completed (empty) slot so one bad
        // service can't wedge the whole read to the timeout.
        guard let ch = s.characteristics?.first else { received += 1; return finish() }
        p.readValue(for: ch)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        // .withResponse: a successful callback means the GATT write landed — that is the confirmation.
        if let e = error { die("write failed: \(e)") }
        done = true; print(names[Int(want!)]); c.cancelPeripheralConnection(p); exit(0)
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if error == nil, let v = ch.value?.first {  // status path only; a failed read just leaves that slot out
            if ch.uuid == chr { mode = v } else if let u = ch.service?.uuid { bat[u] = v }
        }
        received += 1; finish()
    }
    func finish() {
        guard received >= expected else { return }
        done = true
        print(mode.map { $0 < 3 ? names[Int($0)] : "unknown mode \($0)" } ?? "unknown")
        for b in batSvcs { if let lvl = bat[b.uuid] { print("\(b.label.padding(toLength: 6, withPad: " ", startingAt: 0))\(lvl)%") } }
        if let d = dev { c.cancelPeripheralConnection(d) }; exit(0)
    }
}

let arg = CommandLine.arguments.dropFirst().first ?? ""
if arg == "selftest" {
    assert(modes["on"] == 0 && modes["off"] == 1 && modes["transparency"] == 2 && names.count == 3 && batSvcs.count == 3)
    let a = UUID(), b = UUID()
    assert(chooseCandidate([(a, -90)], floor: -70) == a)              // lone device accepted even if weak (it's yours)
    assert(chooseCandidate([(a, -50), (b, -80)], floor: -70) == a)    // ambiguous → strongest above the floor
    assert(chooseCandidate([(a, -80), (b, -85)], floor: -70) == nil)  // ambiguous, all too far → none
    assert(chooseCandidate([], floor: -70) == nil)
    print("ok"); exit(0)
}
guard arg == "status" || modes[arg] != nil else { print("usage: anc on|off|transparency|status"); exit(2) }
let anc = ANC(want: modes[arg])
RunLoop.main.run(until: Date().addingTimeInterval(timeout))
anc.die("timed out (earbuds not found or not responding)")
