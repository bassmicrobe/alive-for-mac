# Notice

**Alive for Mac** is an unofficial macOS port of **Alive** by RueBlose
(<https://github.com/rueblose/alive>), a catalog for Ableton Live projects, plugins and samples.
It is not made, reviewed or endorsed by the original author.

## Licenses

- The original Alive is distributed under the MIT License. Its license text and copyright notice
  are kept unchanged in [`../LICENSE`](../LICENSE) at the repository root, and a verbatim copy
  ships inside the app bundle (`Contents/Resources/LICENSE`).
- The macOS port (everything under `macos/` and `.github/`) is distributed under the MIT License
  in [`LICENSE`](LICENSE), which repeats the original notice alongside the port's own.
- The port reuses from the original: the product design and behaviour, the application icon,
  the on-disk data formats, the `.als` format notes in `FORMAT.md`, and logic translated from
  the C# sources into Swift.

## Third-party code

None. The app uses only Apple system frameworks (Foundation, SwiftUI, AppKit, AVFoundation,
MediaPlayer, CoreServices) and the system zlib library that ships with macOS.

## Trademarks

Ableton, Live, Max for Live and Push are trademarks of Ableton AG. VST is a trademark of
Steinberg Media Technologies GmbH. Audio Units, macOS and Finder are trademarks of Apple Inc.
This project is not affiliated with, sponsored by or endorsed by any of them.
