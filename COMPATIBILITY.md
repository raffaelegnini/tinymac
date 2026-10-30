# Compatibility with TinyTask

TinyMac works like TinyTask 1.77 for Windows, so recordings, settings and habits carry over. This document
covers what is needed for that compatibility: the recording file format, the settings file and the observable
behaviour that TinyMac reproduces.

## Recording files (`.rec`)

A recording is a flat array of 20-byte records with no header. Each record holds five little-endian 32-bit
fields, the same layout as the Win32 `EVENTMSG` structure.

| Offset | Field | Meaning |
|---|---|---|
| 0 | `message` | Event type (see below). `0` ends the recording. |
| 4 | `paramL` | Key: `scan << 8 \| vk`. Mouse: x. |
| 8 | `paramH` | Key: scan code. Mouse: y. |
| 12 | `time` | Timestamp in milliseconds. Only the differences between records matter. |
| 16 | `hwnd` | Identifier of the foreground window at record time. |

| `message` | Event |
|---|---|
| `0x100` / `0x101` | Key down / key up (Windows virtual-key code in the low byte of `paramL`) |
| `0x200` | Mouse move |
| `0x201` / `0x202` | Left button down / up |
| `0x204` / `0x205` | Right button down / up |

Keys use Windows virtual-key codes on both platforms. TinyMac maps them to Mac keys using the US layout
position. Mouse coordinates are screen coordinates: pixels on Windows, points on macOS.

TinyMac flags a file as possibly invalid unless it meets all of these conditions:

- it holds at least 2 bytes;
- its first byte is 0;
- its size is a multiple of 20.

You can load a flagged file anyway.

## Settings

TinyMac keeps the TinyTask settings file format. It uses a `[TinyTask]` section with the same keys:

| Key | Values |
|---|---|
| `window_x`, `window_y` | Window position (top-left) |
| `speed` | `0` = 1x, `1` = ½x, `2` = 2x, `100` = 100x, any other value = custom multiplier |
| `speed_custom` | Custom multiplier, 1–1000 (default 8) |
| `record_key`, `play_key` | `0` = Ctrl+Shift+Alt+R / P, `1` = Print Screen, `8` = F8, `12` = F12 |
| `topmost` | `1` = always on top |
| `hide_captions` | `12` = captions hidden, `0` = shown |
| `toolbar_padding` | Space between buttons (default 5) |
| `toolbar_image` | Path of a custom toolbar image |

TinyMac stores the file at `~/Library/Application Support/TinyMac/TinyMac.ini`. Neither TinyTask nor TinyMac
saves the loop count or the continuous playback setting.

## Behaviour

- **Recording.** TinyMac samples the keyboard and mouse every 10 ms and records at most one key or button
  change per sample. When nothing changed, it records the mouse position instead. When recording stops, the
  final click on TinyMac's own Stop button is removed.
- **Playback.** TinyMac replays each event after the recorded gap, scaled by the speed setting:
  - ½x doubles every gap.
  - 2x and custom speeds divide every gap by the multiplier.
  - 100x also skips most intermediate mouse moves.
- **Loops.** Playback repeats for the set number of loops, or forever in continuous mode. Held keys are
  released before each loop. When the recording contains a left click, there is a short pause between loops.
- **Stopping playback.** Press the play hotkey again, or press Pause or Scroll Lock.
- **Window title.** While recording, the title shows `REC mm:ss`. While playing, it shows
  `mm:ss (loop/total)`, with `*` in continuous mode.
- **Compile.** Creates a standalone program that plays the recording with the current speed and loop count
  without showing a window, then quits. TinyTask creates an `.exe`; TinyMac creates an `.app`.
- **Custom toolbar.** The image is a horizontal strip of 7 equal sprites in this order: Open, Save, Rec,
  Play, Compile, Prefs, then the Rec sprite shown while recording. The colour of the top-left pixel is
  transparent.

TinyMac also reproduces these TinyTask behaviours, so both programs act the same way:

- A custom speed of 1 plays at ½x.
- Pressing Rec during playback stops it and cuts the recording at the current position.
- Saving after stopping a playback early saves only up to that point.
- The middle mouse button is not replayed as a click.
- The scroll wheel is not recorded.

## macOS differences

| TinyTask (Windows) | TinyMac (macOS) |
|---|---|
| Alt | Option (⌥) |
| Print Screen / Scroll Lock / Pause | F13 / F14 / F15 (Apple extended keyboard layout) |
| Compile to `.exe` | Compile to `.app` (ad-hoc signed) |
| Settings next to the `.exe` | `~/Library/Application Support/TinyMac/` |
| Hotkeys | Fire once per press |
| Overwriting a file | The save dialog asks for confirmation |

TinyMac needs Accessibility permission to replay input and Input Monitoring permission to record it.
