# Contributing

Thanks for helping make the utility safer and more useful.

## Reports

For bugs or compatibility reports, include:

- receiver variant;
- receiver firmware version;
- macOS version and Mac architecture;
- whether status polling works;
- the selected USB audio mode; and
- clear reproduction steps.

Do not post device serial numbers, updater credentials, or proprietary firmware images.

## Protocol research

Treat all undocumented setters as potentially state-changing. Prefer static analysis and getters first. Before a live experiment:

1. identify the exact target and payload;
2. record the current value when possible;
3. define and test a recovery value;
4. avoid firmware, pairing, calibration, and factory-data commands; and
5. validate the observable hardware/audio result.

Please document negative results too. A completed HID write is not proof that a command was accepted.

## Building and testing

Run:

```sh
make clean
make app
codesign --verify --deep --strict "build/Lark M2 Status.app"
```

Changes to routing or command framing should be tested with a real receiver and followed by **Restore Mono & Restart**. Pull requests should explain the tested hardware/firmware and leave the receiver in a known safe state.
