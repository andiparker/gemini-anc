import IOBluetooth
import Foundation
setbuf(stdout, nil)
// Throwaway: can we open raw L2CAP to ATT PSM (0x1F) over BR/EDR and talk GATT?
final class L: NSObject, IOBluetoothL2CAPChannelDelegate {
    func l2capChannelData(_ c: IOBluetoothL2CAPChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        print("<-", Data(bytes: p, count: n).map { String(format: "%02x", $0) }.joined(separator: " "))
    }
    func l2capChannelClosed(_ c: IOBluetoothL2CAPChannel!) { print("closed") }
    func l2capChannelOpenComplete(_ c: IOBluetoothL2CAPChannel!, status: IOReturn) { print("open complete", status) }
}
let dev = (IOBluetoothDevice.pairedDevices() as! [IOBluetoothDevice]).first { ($0.name ?? "").contains("Gemini") }!
let l = L(); var ch: IOBluetoothL2CAPChannel?
let r = dev.openL2CAPChannelSync(&ch, withPSM: 0x001F, delegate: l)
print("open l2cap psm 0x1f:", r == kIOReturnSuccess ? "ok" : String(format: "err 0x%x", r))
if let ch {
    var mtu: [UInt8] = [0x02, 0x00, 0x02]  // ATT Exchange MTU 512
    print("write:", ch.writeSync(&mtu, length: 3))
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    var rbgt: [UInt8] = [0x10, 0x01, 0x00, 0xff, 0xff, 0x00, 0x28] // Read By Group Type: primary services
    print("write:", ch.writeSync(&rbgt, length: 7))
    RunLoop.main.run(until: Date().addingTimeInterval(2))
}
