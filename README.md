# Lark M2 Utility for macOS

An experimental native macOS menu-bar utility for the Hollyland LARK M2 USB camera receiver.

It shows both transmitters' connection and battery status and exposes several useful controls that are present in the receiver firmware but unavailable through the normal USB audio interface.

> [!IMPORTANT]
> This is an independent community project. It is not affiliated with or endorsed by Hollyland. The app is still being tested; use the recovery command if another application stops receiving the expected audio layout.

## What it does

- Shows Mic 1 and Mic 2 connection state and reported battery percentage.
- Shows and changes receiver gain from level 0 through 5.
- Turns noise cancellation Off, Weak, or Strong.
- Switches USB audio between:
  - **Mono:** the normal duplicated mix on both advertised USB channels.
  - **Stereo:** Mic 1 on the left channel and Mic 2 on the right channel.
- Remembers the selected USB routing and reapplies stereo after USB reconnects.
- Restarts the receiver or restores compatible mono and restarts as a recovery action.
- Uses no analytics, network requests, audio capture, microphone permission, kernel extension, or firmware modification.

## Status and compatibility

The stereo route was discovered in official RX firmware `V2.0.0.33` and hardware-tested on a camera receiver running `V2.0.0.32` (USB VID `0x3547`, PID `0x0007`). The current build targets Apple silicon and macOS 13 or later.

Other LARK M2 receiver variants and firmware releases have not yet been tested. Please include the receiver type, firmware version, and macOS version when filing an issue. Do not include your device serial number.

## Download

This project is pre-release. Until a tested release is published, build it from source or download a successful Actions artifact.

The generated app is ad-hoc signed, not Developer ID signed or notarized. On first launch macOS may require you to Control-click the app, choose **Open**, and confirm. Do not bypass Gatekeeper for a build obtained anywhere other than this repository.

## Build

Requirements:

- macOS 13 or later
- Apple silicon
- Xcode command-line tools

```sh
git clone https://github.com/bluecoconut/lark-m2-macos.git
cd lark-m2-macos
make app
open "build/Lark M2 Status.app"
```

Create a distributable archive with:

```sh
make release
```

GitHub Actions builds the app on pushes and pull requests. A future tag matching `v*` will also publish the zip as a GitHub Release asset.

## How stereo works

The receiver already advertises a two-channel 48 kHz USB Audio Class input, but its normal mode duplicates one mixed signal into both channels. Its firmware also contains a runtime UAC upload-mix mode that preserves the two wireless streams separately.

The app performs the receiver's temporary product-command handshake and selects that existing mode. It does not replace USB descriptors, patch code, or write firmware. The receiver returns to mono after a USB reconnect, so the app reapplies the user's saved choice when it sees the receiver again.

For the full protocol, command map, experimental evidence, and implementation guidance, see [Protocol notes](docs/PROTOCOL.md). The longer reverse-engineering story is in [How this was discovered](docs/DISCOVERY.md).

## Safety and recovery

**Restore Mono & Restart** sends the known compatible mode, then uses the receiver's ordinary restart command. It also changes the app's saved preference back to mono so stereo is not reapplied on reconnect.

The stereo mode and product-command acceptance flag are runtime state. The app never invokes the firmware-upgrade commands or writes receiver flash.

## Contributing

Hardware reports and carefully scoped protocol research are welcome. Keep experiments reversible, record the exact receiver and firmware version, validate observable behavior, and avoid uploading Hollyland firmware or device serial numbers. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Third-party software

The build vendors the macOS implementation of [hidapi](https://github.com/libusb/hidapi). Its license is included at `ThirdParty/hidapi/LICENSE.txt`.

## License

MIT. See [LICENSE](LICENSE).
