# LARK M2 USB/HID protocol notes

These notes describe the portions of the camera receiver protocol used by this app. They are intended to make independent implementations and further cautious research possible.

## Tested device

| Property | Value |
| --- | --- |
| USB product | `Wireless microphone` |
| USB vendor ID | `0x3547` |
| USB product ID | `0x0007` |
| Live-tested RX firmware | `V2.0.0.32` |
| Firmware analyzed | official RX `V2.0.0.33` |
| USB audio input | 48 kHz, two channels |

No serial numbers are needed by the app and none are included here.

## Standard reports

The normal control path uses HID report ID `0x55`. The host writes a full 64-byte report:

```text
55 AA DD CMD TARGET LEN_H LEN_L PAYLOAD... XOR 00...
```

- `55` is the HID report ID.
- Host synchronization bytes are `AA DD`; receiver responses begin `BB DD`.
- `TARGET` is `40` for the receiver, `41` for TX1, and `42` for TX2.
- The response targets are `80`, `81`, and `82` respectively.
- Length is big-endian.
- `XOR` is the XOR of the logical packet from `AA` through the final payload byte. It excludes the HID report ID and zero padding.
- Writes are padded to exactly 64 bytes.

The receiver can acknowledge some setters and leave others fire-and-forget. Drain an optional reply before issuing the next query, then use heartbeat state as the authoritative readback.

### Commands used by the app

| Command | Direction | Payload | Meaning |
| --- | --- | --- | --- |
| `0x05` | Set | one byte, `0`–`5` | receiver gain |
| `0x06` | Set | `1` weak, `2` strong | noise-cancellation strength |
| `0x0C` | Set | none | restart receiver |
| `0x10` | Get | none | heartbeat/status |
| `0x19` | Set | `0` off, `1` on | noise-cancellation enable |

The strength is sent before enable when selecting Weak or Strong. Turning noise cancellation off sends `0x19 = 0` without changing the stored strength.

### Heartbeat

The confirmed heartbeat request prefix is:

```text
55 AA DD 10 40 00 00 27
```

The observed nine-byte response payload is:

| Offset | Meaning |
| ---: | --- |
| `0` | TX1 connected (`1` = yes) |
| `1` | TX2 connected (`1` = yes) |
| `2` | TX1 battery value |
| `3` | TX2 battery value |
| `4..5` | UV/status value |
| `6` | noise-cancellation state/level |
| `7` | gain level |
| `8` | voice-lock state |

The battery values behave like percentages, though a complete discharge-cycle characterization would still be useful.

## Product reports and independent channels

The hidden UAC mix control uses HID report ID `0x05` and a shorter logical header:

```text
05 AA DD CMD LEN_H LEN_L PAYLOAD... XOR 00...
```

The app first sends the temporary product-command handshake:

```text
05 AA DD FF 00 00 88
```

It then selects the UAC upload mix mode with product command `0x25`:

```text
05 AA DD 25 00 01 00 53  # compatible duplicated mono
05 AA DD 25 00 01 01 52  # Mic 1 left, Mic 2 right
```

The receiver replies on report ID `0x05` with `BB DD`, the command, a two-byte length, an echoed mode byte, and XOR. A rejected mode request was observed to echo `FF`; implementations should verify the echoed value rather than treating a successful USB write as acceptance.

Mode `2` exists in the decoded setter but has not been characterized and is not exposed by the app.

### Runtime behavior

- Product-command acceptance is a RAM-only flag.
- The mix-mode setter changes the active audio-engine route without flashing or USB re-enumeration.
- A receiver restart clears the temporary product-command flag.
- The receiver's USB-connect path returns the upload mix to mode `0`, so applications that offer persistent stereo must deliberately reapply mode `1` after reconnect.
- Normal heartbeat commands continue working after the product handshake.

## Live audio evidence

The reversible test captured the receiver's advertised two-channel PCM stream before, during, and after mode `1`:

| State | Frames | Frames where L != R | Correlation |
| --- | ---: | ---: | ---: |
| Baseline mode `0` | 255,744 | 0.00% | 1.000000 |
| Mode `1` | 339,968 | 98.88% | 0.927224 |
| Restored mode `0` | 213,888 | 0.00% | 1.000000 |

An end-to-end test through this app produced 166,720 differing frames out of 168,960 (98.67%). After **Restore Mono & Restart**, a new 119,936-frame capture had zero differing left/right frames.

## Other command leads

Firmware and community mappings contain leads for analog monitor output, voice lock, shutdown time, transmitter-button customization, and LED control. They are intentionally not documented as stable commands here because their exact scope, persistence, and payload semantics have not all been validated on LARK M2 hardware.

If you investigate them, begin with getters and static call-site analysis. Before sending a setter, establish a reversible value, preserve the current state, avoid pairing/update commands, and verify the physical effect rather than inferring success from the HID write.

## Implementation cautions

- Open the correct HID interface by VID/PID and serialize access from polling and controls.
- Drain stale input before an exchange.
- Write all 64 bytes, including report ID and padding.
- Validate synchronization bytes, command, length, and echoed product-mode value.
- Close and reopen HID on malformed replies or USB disconnect.
- Do not automatically persist unknown receiver state.
- Provide a visible mono-and-restart recovery path.
