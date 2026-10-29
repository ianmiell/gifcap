# AGENTS.md

Notes for coding agents working on gifcap. See README.md for what it does and how people use it.

## Layout

- `gifcap.swift` is the whole program, one file, no package manager and no dependencies beyond AppKit and ScreenCaptureKit. In order: option parsing and `fail()`, the drag-to-select overlay (`SelectionView`), the red border shown while recording (`BorderView`), then `Controller`, which records a `.mov` with `SCRecordingOutput` and converts it to a GIF by running ffmpeg.
- `gifcap` is a bash wrapper that compiles `gifcap.swift` into `${XDG_CACHE_HOME:-~/.cache}/gifcap/gifcap` when the source is newer than the binary, then runs it.
- `gifcap-app` builds, ad-hoc signs and installs `gifcap.app` and adds it to the Dock.
- `gifcap-icon.swift` draws the app icon into an `.iconset` for `iconutil`.

The scripts resolve their own directory with `readlink -f`, so they work when symlinked onto `PATH` (for example from `~/git/work/bin/mac`). Keep it that way.

## Building and checking

There are no tests. After a change, at least make sure it compiles:

```
swiftc -O -o /tmp/gifcap gifcap.swift      # or just run ./gifcap -h
swift gifcap-icon.swift /tmp/gifcap.iconset # if you touched the icon
bash -n gifcap gifcap-app                   # syntax-check the scripts
```

Recording needs a person: it waits for a mouse drag and needs Screen Recording permission, so an agent can't test it end to end. Say so rather than claiming it works, and suggest what the user should try.

Don't run `gifcap-app` unless asked. It replaces the installed app, restarts the Dock, and makes macOS ask for Screen Recording permission again.

## Conventions

- Swift uses 4-space indentation. Bash uses tabs.
- Each file starts with a comment saying what it is and how it's run. Update it if that changes.
- Comments explain why, not what (for example why ffmpeg gets its own process group, why `screencapture -v` isn't used).
- Errors go through `fail()`, prefixed `gifcap: `. It prints to stderr from a terminal and shows an alert when running as the app (`isApp`). Don't call `exit()` directly for errors.
- When you add or change an option, update `usage` in `gifcap.swift` and the copy of it in README.md.
- Behaviour must work both from a terminal and as `gifcap.app` (which acts as if `-r` were given). Check both paths when touching startup, output or error handling.
- Target macOS 15+ (`LSMinimumSystemVersion` in `gifcap-app`). Don't add third-party dependencies. ffmpeg is the only external tool, found by `findFFmpeg()`.
