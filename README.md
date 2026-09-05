# gemini-anc

Control active noise cancellation on **Devialet Gemini II** earbuds from macOS,
over BLE — no phone app needed. A single Swift file talking to the Devialet
Audio GATT service.

## Build

```sh
swiftc -O anc.swift -o anc
```

## Usage

```sh
anc on            # noise cancellation
anc off           # neutral
anc transparency  # let ambient sound through
anc status        # print the current mode
```

Bluetooth must be on and the buds powered/in range. First run scans for the
buds; later runs reconnect directly (see below).

## How it works

The buds don't advertise a name or service UUID, so the tool finds them by
Devialet's Bluetooth company id (`0x0258`) in the manufacturer data, connects to
the Audio service, and reads/writes the `CurrentAncConfiguration` characteristic
(`uint8`: `0` on / `1` off / `2` transparency).

After the first connect it caches the peripheral's UUID to `~/.anc-peer` and
reconnects to it directly on later runs, skipping the scan-for-advertisement
wait. Warm runs are ~1.5–2.5s versus ~8–13s cold. If the cached device is stale
or out of range, it falls back to a fresh scan.

## `spike/`

Throwaway BLE exploration scripts used to reverse the protocol (GATT dump,
scanning, GAIA probing, etc.). Not needed to use the tool.

## Notes

- macOS only (uses CoreBluetooth).
- Unofficial and unaffiliated with Devialet. Protocol found by inspection; may
  break with firmware changes.
