# RodeWakeFix

RodeWakeFix is a small, local macOS helper for the RØDE NT-USB Mini. It watches
sleep and wake events, remembers whether the RØDE was the selected input before
sleep, and restores it after wake when macOS still exposes the device to
CoreAudio.

The app is deliberately conservative: it does not restart CoreAudio or record
audio. An optional "Always prefer RØDE" setting can restore the RØDE when macOS
changes the system input while the microphone is connected.

## Requirements

- macOS 13 or newer
- Xcode 15 or newer

## Open and run

Open `RodeWakeFix.xcodeproj`, select the `RodeWakeFix` scheme, and press Run.

The app is an accessory app, so it has no Dock icon. It provides a microphone
icon in the menu bar for quickly switching the macOS default input, checking the
RØDE state, and seeing the result of the most recent wake check. When launched
normally it also opens a small status window. When launched by its user
LaunchAgent with `--background`, it starts with only the menu-bar icon visible.

## Behaviour

- Targets the RØDE NT-USB Mini with serial number `ACAAF915`.
- If another microphone was selected before sleep, it does nothing after wake.
- If the RØDE was selected and returns through CoreAudio, it restores it as the
  system default input.
- If USB still sees the RØDE but CoreAudio does not, it records the condition in
  the local log for the next repair stage.
- If the RØDE is unplugged, it does nothing.
- "Always prefer RØDE when connected" is off by default. When enabled, the app
  observes CoreAudio input changes and restores the RØDE after a short debounce.
- Selecting a different microphone from the app's menu turns that preference
  off, so a manual override is never immediately undone.

Logs are stored at `~/Library/Logs/RodeWakeFix/RodeWakeFix.log`.

## Privacy

RodeWakeFix only reads USB and CoreAudio device metadata. It does not open the
microphone, capture audio, or use the network.

## Repository

This directory is intended to be its own Git repository. Build products and
Xcode user state are ignored.
