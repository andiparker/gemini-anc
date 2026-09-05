import IOBluetooth
for d in IOBluetoothDevice.pairedDevices() as! [IOBluetoothDevice] {
    guard (d.name ?? "").contains("Gemini") else { continue }
    print("device:", d.name!, d.addressString!, "connected:", d.isConnected())
    d.performSDPQuery(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    for r in (d.services as? [IOBluetoothSDPServiceRecord]) ?? [] {
        var ch: BluetoothRFCOMMChannelID = 0
        let hasRF = r.getRFCOMMChannelID(&ch) == kIOReturnSuccess
        print("  svc:", r.getServiceName() ?? "?", hasRF ? "rfcomm ch \(ch)" : "", "uuids:", r.attributes?[1] as Any)
    }
}
