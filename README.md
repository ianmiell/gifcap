# gifcap

Drag-select a region of the screen on macOS, record it, and get an animated GIF.

Recording uses ScreenCaptureKit and conversion uses ffmpeg. The GIF goes to `~/Desktop` by default, its path is printed, and the file is put on the clipboard.

## Requirements

- macOS 15 or later
- Xcode command line tools (`swiftc`)
- ffmpeg (`brew install ffmpeg`)

## Command line

Put this directory (or a symlink to `gifcap`) on your `PATH` and run:

```
gifcap [-f fps] [-s scale] [-d seconds] [-o dir] [-k] [-m] [-r]
  -f fps      frames per second in the GIF (default 15)
  -s scale    size relative to the selection in points; 2 = full Retina (default 1)
  -d seconds  stop automatically after this many seconds
  -o dir      where to write the GIF (default ~/Desktop)
  -k          show mouse clicks in the recording
  -m          keep the intermediate .mov next to the GIF
  -r          reveal the GIF in Finder when done
```

Drag to select a region (Esc cancels). Stop with the Stop button, the menu bar item or Ctrl-C.

The `gifcap` wrapper compiles `gifcap.swift` into `~/.cache/gifcap/` on first run and whenever the source changes. The terminal app you run it from needs Screen Recording permission in System Settings > Privacy & Security.

## App

```
./gifcap-app [install-dir]   # default ~/Applications
```

This builds `gifcap.app` (with an icon drawn by `gifcap-icon.swift`), installs it and adds it to the Dock. Launching the app is the same as `gifcap -r`: errors show as alerts and the GIF is revealed in Finder.

The app is ad-hoc signed, so macOS asks for Screen Recording permission again after every rebuild. If it gets stuck, remove the old gifcap entry in System Settings.
