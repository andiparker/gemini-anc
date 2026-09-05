import IOBluetooth
import Foundation
setbuf(stdout, nil)

// Throwaway GAIA probe over RFCOMM ch 15. Frame: FF 01 flags len vendor(2) cmd(2) payload
final class Link: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var buf = Data()
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        buf.append(Data(bytes: p, count: n))
        while buf.count >= 8, buf[0] == 0xFF {
            let len = Int(buf[3]); let total = 8 + len + (buf[2] & 1 == 1 ? 1 : 0)
            guard buf.count >= total else { break }
            let f = Data(buf.prefix(total)); buf = Data(buf.dropFirst(total))
            let vendor = (UInt16(f[4]) << 8) | UInt16(f[5]); let cmd = (UInt16(f[6]) << 8) | UInt16(f[7])
            let feat = cmd >> 9, pdu = (cmd >> 7) & 3, spec = cmd & 0x7F
            print(String(format: "<- vendor %04x cmd %04x (feat %d pdu %d id %d) payload %@", vendor, cmd, feat, pdu, spec, f.dropFirst(8).hex))
        }
        if !buf.isEmpty && buf[0] != 0xFF { print("junk:", buf.hex); buf.removeAll() }
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { print("closed"); exit(1) }
}
extension Data { var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") } }

func send(_ ch: IOBluetoothRFCOMMChannel, vendor: UInt16, feat: UInt16, id: UInt16, payload: [UInt8] = []) {
    let cmd = (feat << 9) | id
    var f: [UInt8] = [0xFF, 0x01, 0x00, UInt8(payload.count), UInt8(vendor >> 8), UInt8(vendor & 0xFF), UInt8(cmd >> 8), UInt8(cmd & 0xFF)] + payload
    print(String(format: "-> vendor %04x feat %d id %d payload %@", vendor, feat, id, Data(payload).hex))
    let r = ch.writeSync(&f, length: UInt16(f.count)); if r != kIOReturnSuccess { print("write err", r) }
}

let dev = (IOBluetoothDevice.pairedDevices() as! [IOBluetoothDevice]).first { ($0.name ?? "").contains("Gemini") }!
let link = Link()
var ch: IOBluetoothRFCOMMChannel?
var chan: BluetoothRFCOMMChannelID = 0
dev.performSDPQuery(nil); RunLoop.main.run(until: Date().addingTimeInterval(2))
for r in (dev.services as? [IOBluetoothSDPServiceRecord]) ?? [] where r.getServiceName() == "GAIA" { _ = r.getRFCOMMChannelID(&chan) }
let r = dev.openRFCOMMChannelSync(&ch, withChannelID: chan, delegate: link)
print("open rfcomm \(chan):", r == kIOReturnSuccess ? "ok" : String(format: "err 0x%x", r))
guard let ch else { exit(1) }
let args = CommandLine.arguments.dropFirst().map { UInt16($0, radix: 16)! } // vendor feat id [payload bytes...]
if args.count >= 3 {
    send(ch, vendor: args[0], feat: args[1], id: args[2], payload: args.dropFirst(3).map { UInt8($0) })
} else {
    send(ch, vendor: 0x001D, feat: 0, id: 0)   // get API version
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    for (feat, id, pl) in [(0,1,[]), (8,1,[]), (8,3,[]), (8,4,[]), (2,1,[]), (2,4,[])] as [(UInt16,UInt16,[UInt8])] {
        send(ch, vendor: 0x001D, feat: feat, id: id, payload: pl)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }
}
RunLoop.main.run(until: Date().addingTimeInterval(3))
