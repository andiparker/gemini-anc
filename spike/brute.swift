import IOBluetooth
import Foundation
setbuf(stdout, nil)
// Throwaway: paced sweep of GAIA vendor IDs (one in flight), print any reply that isn't "unknown vendor" (error 01).
final class Link: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var buf = Data(); var hits = 0; var waiting: UInt16? = nil
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data p: UnsafeMutableRawPointer!, length n: Int) {
        buf.append(Data(bytes: p, count: n))
        while buf.count >= 8, buf[0] == 0xFF {
            let len = Int(buf[3]); let total = 8 + len + (buf[2] & 1 == 1 ? 1 : 0)
            guard buf.count >= total else { break }
            let f = Data(buf.prefix(total)); buf = Data(buf.dropFirst(total))
            let vendor = (UInt16(f[4]) << 8) | UInt16(f[5]); let cmd = (UInt16(f[6]) << 8) | UInt16(f[7])
            let pl = f.dropFirst(8)
            let unknown = (cmd & 0x180) == 0x180 && pl.count == 1 && pl.first == 1
            if !unknown { hits += 1; print(String(format: "HIT vendor %04x cmd %04x payload %@", vendor, cmd, pl.map { String(format: "%02x", $0) }.joined(separator: " "))) }
            if vendor == waiting { waiting = nil }
        }
        if !buf.isEmpty && buf[0] != 0xFF { buf.removeAll() }
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { print("closed"); exit(1) }
}
let dev = (IOBluetoothDevice.pairedDevices() as! [IOBluetoothDevice]).first { ($0.name ?? "").contains("Gemini") }!
var chan: BluetoothRFCOMMChannelID = 0
dev.performSDPQuery(nil); RunLoop.main.run(until: Date().addingTimeInterval(2))
for r in (dev.services as? [IOBluetoothSDPServiceRecord]) ?? [] where r.getServiceName() == "GAIA" { _ = r.getRFCOMMChannelID(&chan) }
let link = Link(); var ch: IOBluetoothRFCOMMChannel?
guard dev.openRFCOMMChannelSync(&ch, withChannelID: chan, delegate: link) == kIOReturnSuccess, let ch else { print("open failed"); exit(1) }
let lo = Int(CommandLine.arguments[1], radix: 16)!, hi = Int(CommandLine.arguments[2], radix: 16)!
let t0 = Date(); var timeouts = 0
for v in lo...hi {
    if v == 0x001D || v == 0x000A { continue }
    var f: [UInt8] = [0xFF, 0x01, 0x00, 0x00, UInt8(v >> 8), UInt8(v & 0xFF), 0x00, 0x00]
    link.waiting = UInt16(v)
    guard ch.writeSync(&f, length: 8) == kIOReturnSuccess else { print("write failed at", String(format: "%04x", v)); exit(1) }
    let deadline = Date().addingTimeInterval(0.5)
    while link.waiting != nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    if link.waiting != nil { timeouts += 1; print(String(format: "timeout %04x", v)); if timeouts > 20 { exit(1) } }
    if v % 1024 == 0 { print(String(format: "...%04x  %.1fs elapsed", v, Date().timeIntervalSince(t0))) }
}
print("done, hits:", link.hits, "timeouts:", timeouts, String(format: "%.1fs", Date().timeIntervalSince(t0)))
