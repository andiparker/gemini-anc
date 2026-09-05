import IOBluetooth
let dev = (IOBluetoothDevice.pairedDevices() as! [IOBluetoothDevice]).first { ($0.name ?? "").contains("Gemini") }!
print("close:", dev.closeConnection()); RunLoop.main.run(until: Date().addingTimeInterval(3))
print("open:", dev.openConnection()); RunLoop.main.run(until: Date().addingTimeInterval(3))
print("connected:", dev.isConnected())
