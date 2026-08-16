# How the independent USB channels were discovered

This began with a simple contradiction: macOS reported a two-channel USB microphone, but every captured left/right sample was identical. Either the two transmitters were being mixed before USB, or the receiver contained a route that its public interface did not expose.

## 1. Establishing the baseline

The connected camera receiver identified as USB VID `0x3547`, PID `0x0007`, with a two-channel 48 kHz input. A PCM capture confirmed that the channels were bit-for-bit duplicated mono.

The receiver also exposed a proprietary HID interface. Observing the official desktop updater and testing read-only queries established the `0x55` report framing, target identifiers, XOR checksum, version queries, serial query, and nine-byte heartbeat. That yielded separate TX connection flags, separate battery values, noise state, and gain.

## 2. Obtaining an analyzable receiver image

Hollyland's updater backend offered official RX firmware `V2.0.0.33` while the connected receiver remained on `.32`. The package was downloaded for offline analysis only; it was never flashed.

The RX update was an `AOTA` container holding several partitions. Its outer partition covering was a repeating XOR mask recoverable from erased/padding regions. The main application was an Actions Semiconductor `ACTH` container with an additional vendor transform and segmented compression.

Static analysis of Actions' own update tooling revealed the transform parameters and recurrence:

- initial randomizer key `0`;
- restart/randomize unit `0x202` in the update configuration;
- application records resetting the stream state at `0x20`-byte boundaries;
- seventeen raw-LZMA segments with property byte `0x5D` and 16 MiB dictionaries.

All seventeen segments decompressed successfully into a 1,205,824-byte ARM Thumb receiver application identifying itself as `HL_A6301_V2.0.0.33_RX`. This work was about understanding the application; the repository does not redistribute Hollyland firmware or vendor tools.

## 3. Following the audio path

The decoded application contained a mic PCM upload handler with two distinct wireless source buffers. The streams were therefore still independent inside the receiver before final USB mixing.

Following that path found `tr_usound_set_uac_upload_mix_mode`. It accepts modes `0`, `1`, and `2`, sends an audio-engine control, and records the selected upload mix mode. A product-test HID handler maps command `0x25` (`PDT_SET_MIX`) directly to this callback.

Another handler enabled temporary product-command acceptance through command `0xFF`. Importantly, the acceptance state was a RAM bit, not a flash write.

## 4. Performing a reversible test

The live test was deliberately bounded:

1. Capture baseline PCM.
2. Send the product handshake.
3. Select UAC mix mode `1` and validate the echoed reply.
4. Capture PCM again without flashing or re-enumerating USB.
5. Restore mode `0` and validate the echo.
6. Capture again and confirm ordinary heartbeat/version queries still worked.

Mode `1` made 98.88% of captured frames differ between left and right. The right channel was not a fixed-gain copy of the left, and firmware showed two distinct source buffers. Restoring mode `0` returned to zero differing frames.

The same path worked on the connected `.32` receiver even though it was discovered in `.33`, showing that the feature predates the analyzed update.

## 5. Turning the finding into an app

The menu-bar app keeps all HID work on one serial queue, polls heartbeat for authoritative state, validates product replies, remembers the user's desired route, and reapplies stereo because the firmware's USB-connect handler resets the mix to mode `0`.

The recovery command first requests mode `0`, changes the saved preference to mono, and then issues the normal receiver restart. A final live test confirmed that this returned a new PCM capture to bit-identical duplicated mono.

## What remains interesting

The firmware contains other controls—LEDs, analog monitoring, voice lock, shutdown timing, and button mapping—but identifying a command number is not enough. Each needs its payload values, target, persistence, interaction with transmitter state, and reversible recovery procedure characterized before it belongs in a user-facing app.

The most useful next research contributions would be:

- testing receiver variants and firmware versions;
- observing transmitter battery values through a discharge cycle;
- characterizing mix mode `2` without assuming its purpose;
- mapping getters and call sites for the unexposed settings; and
- documenting whether stereo survives different hosts, sample formats, and conferencing/recording applications.
