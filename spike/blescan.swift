import CoreBluetooth
import Foundation
setbuf(stdout, nil)
// Throwaway: 40s BLE scan; print any advert carrying Devialet UUIDs / company 0x0258 / a name.
final class S: NSObject, CBCentralManagerDelegate {
    var c: CBCentralManager!; var seen = Set<UUID>()
    override init() { super.init(); c = CBCentralManager(delegate: self, queue: nil) }
    func centralManagerDidUpdateState(_ c: CBCentralManager) { if c.state == .poweredOn { c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) } }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let desc = "\(ad)"
        let mfg = (ad[CBAdvertisementDataManufacturerDataKey] as? Data) ?? Data()
        let devialet = desc.lowercased().contains("6465-7669616c6574") || desc.lowercased().contains("devialet") || (mfg.count >= 2 && mfg[0] == 0x58 && mfg[1] == 0x02)
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String)
        if devialet || (name != nil && !seen.contains(p.identifier)) {
            seen.insert(p.identifier)
            print(devialet ? "DEVIALET" : "named", name ?? "", p.identifier, rssi, desc.replacingOccurrences(of: "\n", with: " "))
        }
    }
}
let s = S(); RunLoop.main.run(until: Date().addingTimeInterval(40))
