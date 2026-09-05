import CoreBluetooth
import Foundation
setbuf(stdout, nil)
// Throwaway: connect to Gemini II over BLE (Devialet mfg id 0x0258), dump all services/chars, read values.
final class P: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var c: CBCentralManager!; var dev: CBPeripheral?; var pending = 0
    override init() { super.init(); c = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { return }
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]); print("scanning")
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        guard dev == nil, let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2, m[0] == 0x58, m[1] == 0x02 else { return }
        c.stopScan(); dev = p; p.delegate = self; print("found", p.identifier, "connecting"); c.connect(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("connected"); p.discoverServices(nil) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("connect failed", error ?? ""); exit(1) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { print("disconnected", error ?? ""); exit(1) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        for s in p.services ?? [] { print("service", s.uuid); p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            var pr: [String] = []
            if ch.properties.contains(.read) { pr.append("R") }; if ch.properties.contains(.write) { pr.append("W") }
            if ch.properties.contains(.writeWithoutResponse) { pr.append("WNR") }; if ch.properties.contains(.notify) { pr.append("N") }; if ch.properties.contains(.indicate) { pr.append("I") }
            print("  char", s.uuid, "/", ch.uuid, pr.joined(separator: ","))
            if ch.properties.contains(.read) { p.readValue(for: ch) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        print("  value", ch.service!.uuid, "/", ch.uuid, "=", ch.value?.map { String(format: "%02x", $0) }.joined(separator: " ") ?? "nil", ch.value.flatMap { String(data: $0, encoding: .utf8) }.map { "\"\($0)\"" } ?? "", error.map { "err \($0)" } ?? "")
    }
}
let p = P(); RunLoop.main.run(until: Date().addingTimeInterval(25))
