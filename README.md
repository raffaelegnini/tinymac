# TinyMac

TinyMac records and replays mouse and keyboard input on macOS. It is a port of
[TinyTask](https://www.tinytask.net) 1.77 for Windows and works the same way: same features, same settings,
same hotkeys and the same `.rec` file format, so recordings move between the two. It uses a native macOS
toolbar.

> TinyMac is an independent project and is not affiliated with or endorsed by the author of TinyTask.
> It is an independent implementation and contains none of TinyTask's code.

## Build

The build needs macOS 13 or later and Xcode or the Command Line Tools (Swift 5.9+).

```bash
./build.sh                  # produces dist/TinyMac.app (universal arm64 + x86_64, signed ad hoc)
cp -R dist/TinyMac.app /Applications/
open /Applications/TinyMac.app
```

On first launch, TinyMac needs two permissions in **System Settings › Privacy & Security**:

- **Accessibility**, to replay input
- **Input Monitoring**, to record input

Grant both, then quit TinyMac (⌘Q) and reopen it. A rebuilt app has a new ad-hoc signature, so you may need to
remove TinyMac from both lists and add it again after each rebuild.

## Usage

| Button | Action |
|---|---|
| **Open** | Load a `.rec` recording (`O` key). |
| **Save** | Save the current recording as `.rec`. |
| **Rec** | Start or stop recording. Default hotkey: Ctrl+Shift+Option+R. |
| **Play** | Play the recording. Default hotkey: Ctrl+Shift+Option+P. Press the hotkey again to stop. F15 (Pause) and F14 (Scroll Lock) also stop playback. |
| **.app** | Compile the recording into a standalone app. The app plays the recording with the current speed and loop count, then quits. |
| **Prefs** | Open the preferences menu (Return key). |

The preferences menu contains:

- Playback speed: ½x, 1x, 2x, 100x or a custom value
- Continuous playback and the number of playback loops
- Record and play hotkeys: Ctrl+Shift+Option+R/P, Print Screen (F13), F8 or F12
- Always on top
- Captions
- Custom toolbar: a strip image with 7 sprites
- Website and About

Keys that Mac keyboards lack use Apple's extended-keyboard equivalents: Print Screen = F13, Scroll Lock = F14,
Pause = F15.

Settings live in `~/Library/Application Support/TinyMac/TinyMac.ini`. The file uses the same `[TinyTask]`
section and keys as the Windows `tinytask.ini`.

## Compatibility

[`COMPATIBILITY.md`](COMPATIBILITY.md) describes:

- the `.rec` file format
- the settings keys
- the behaviour TinyMac shares with TinyTask
- the differences on macOS

## License

MIT. See [`LICENSE`](LICENSE). TinyTask is a separate product of its own author and is not covered by this license.
