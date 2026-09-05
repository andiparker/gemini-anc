import CoreBluetooth
import Foundation

// Throwaway probe: find Gemini II over BLE, dump GATT, subscribe to all notify chars, print changes.
final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var dev: CBPeripheral?
    var chars: [CBCharacteristic] = []
    let deadline = Date().addingTimeInterval(TimeInterval(CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 60))

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("central state:", c.state.rawValue)
        guard c.state == .poweredOn else { return }
        // Already-connected (by system) peripherals first
        let known = c.retrieveConnectedPeripherals(withServices: [])
        print("system-connected peripherals:", known.map { $0.name ?? "?" })
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        print("scanning...")
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data)?.hex ?? ""; if mfg.hasPrefix("4c00") { return }; print("  found:", name.isEmpty ? p.identifier.uuidString : name, rssi, ad)
        let svcs = (ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []; if name.lowercased().contains("gemini") || name.lowercased().contains("devialet") || svcs.contains(CBUUID(string: "331DCAA1-3995-83E8-090A-63782370D984")) {
            c.stopScan(); dev = p; p.delegate = self; c.connect(p); print("connecting to", name)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("connected"); p.discoverServices(nil) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("connect failed:", error ?? "") }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { print("disconnected:", error ?? ""); exit(1) }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { print("service", s.uuid); p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            print("  char", s.uuid, "/", ch.uuid, "props", props(ch.properties))
            chars.append(ch)
            if ch.properties.contains(.read) { p.readValue(for: ch) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] value", ch.service!.uuid, "/", ch.uuid, "=", ch.value?.hex ?? "nil", ch.value.flatMap { String(data: $0, encoding: .utf8) }.map { "\"\($0)\"" } ?? "", error.map { "err \($0)" } ?? "")
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        print("  notify", ch.uuid, ch.isNotifying, error.map { "err \($0)" } ?? "")
    }
    func props(_ p: CBCharacteristicProperties) -> String {
        var o: [String] = []
        if p.contains(.read) { o.append("R") }; if p.contains(.write) { o.append("W") }
        if p.contains(.writeWithoutResponse) { o.append("WNR") }; if p.contains(.notify) { o.append("N") }
        if p.contains(.indicate) { o.append("I") }
        return o.joined(separator: ",")
    }
}
extension Data { var hex: String { map { String(format: "%02x", $0) }.joined() } }

let probe = Probe()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in if Date() > probe.deadline { print("deadline reached"); exit(0) } }
RunLoop.main.run()
