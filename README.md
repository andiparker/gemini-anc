# gemini-anc

Control active noise cancellation on **Devialet Gemini II** earbuds from macOS,
over BLE â no phone app needed. A single Swift file talking to the Devialet
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

## Menu-bar app

A tiny menu-bar front end that shells out to `anc`. Build it as a
double-clickable app:

```sh
./build-app.sh      # builds ANC.app with both binaries bundled
open ANC.app        # or just double-click it in Finder
```

Double-clicking ANC.app launches it straight into the menu bar — no Terminal,
no Dock icon. It shows the current mode with a checkmark and switches modes on
click. Each action does a fresh BLE reconnect, so expect ~1.5–2.5s per click.

To run the front end bare instead: `swiftc -O ancbar.swift -o ancbar && ./ancbar`
(double-clicking the bare binary opens Terminal; the `.app` does not). It finds
the `anc` binary via `$ANC_BIN`, a sibling binary, then `$PATH`.

## Distribution (.dmg)

```sh
./build-dmg.sh      # builds ANC.app, then packages ANC.dmg
```

Opening ANC.dmg shows ANC.app next to an Applications shortcut — drag the app
onto it to install.

The app is **unsigned and not notarized**. On the machine that built it, it
opens normally. Anyone else who downloads the DMG will be blocked by Gatekeeper
and must right-click the app → **Open** the first time. For frictionless
distribution, sign with a Developer ID and notarize (see the commented steps in
`build-dmg.sh`); that needs a paid Apple Developer account.

## How it works

The buds don't advertise a name or service UUID, so the tool finds them by
Devialet's Bluetooth company id (`0x0258`) in the manufacturer data, connects to
the Audio service, and reads/writes the `CurrentAncConfiguration` characteristic
(`uint8`: `0` on / `1` off / `2` transparency).

After the first connect it caches the peripheral's UUID to `~/.anc-peer` and
reconnects to it directly on later runs, skipping the scan-for-advertisement
wait. Warm runs are ~1.5â2.5s versus ~8â13s cold. If the cached device is stale
or out of range, it falls back to a fresh scan.

## Notes

- macOS only (uses CoreBluetooth).
- Unofficial and unaffiliated with Devialet. Protocol found by inspection; may
  break with firmware changes.
