import CoreBluetooth
import Foundation
setbuf(stdout, nil)
let uuids = (1...8).map { CBUUID(string: String(format: "0000d80%d-0000-0000-6465-7669616c6574", $0)) } + [CBUUID(string: "180F"), CBUUID(string: "180A")]
final class P: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var c: CBCentralManager!; var dev: CBPeripheral?
    override init() { super.init(); c = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { return }
        let ps = c.retrieveConnectedPeripherals(withServices: uuids)
        print("connected peripherals w/ devialet svcs:", ps.map { "\($0.name ?? "?") \($0.identifier) state=\($0.state.rawValue)" })
        guard let p = ps.first else { print("none"); exit(0) }
        dev = p; p.delegate = self
        if p.state == .connected { p.discoverServices(nil) } else { c.connect(p) }
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { print("connected"); p.discoverServices(nil) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { print("fail", error ?? ""); exit(1) }
    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        for s in p.services ?? [] { print("service", s.uuid); p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            print("  char", s.uuid, "/", ch.uuid, "props", ch.properties.rawValue)
            if ch.properties.contains(.read) { p.readValue(for: ch) }
            if ch.properties.contains(.notify) || ch.properties.contains(.indicate) { p.setNotifyValue(true, for: ch) }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        print("  value", ch.service!.uuid, "/", ch.uuid, "=", ch.value?.map { String(format: "%02x", $0) }.joined(separator: " ") ?? "nil", error.map { "err \($0)" } ?? "")
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) { print("  notify", ch.uuid, ch.isNotifying, error.map { "err \($0)" } ?? "") }
}
let p = P()
RunLoop.main.run(until: Date().addingTimeInterval(Double(CommandLine.arguments.dropFirst().first ?? "15")!))
