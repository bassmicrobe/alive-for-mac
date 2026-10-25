# Alive for Mac branding

The ten `alive-*.svg` files are the original artwork supplied in `logo-svg.zip`
on 2026-10-25, preserved without modification.

- `alive-logo-dark.svg` / `alive-logo-light.svg`: horizontal wordmarks for dark /
  light backgrounds. Both macOS READMEs switch between them using `<picture>`.
- `alive-mark-*.svg`: standalone marks, including monochrome and white variants.
- `alive-logo-mono.svg` / `alive-logo-white.svg`: alternative wordmarks.
- `alive-appicon-dark.svg` / `alive-appicon-light.svg`: 1024 px app icon artwork.
  The dark version is used for the macOS app, matching its dark interface.

`AppIcon-1024.png` is a rasterization of `alive-appicon-dark.svg`, preserving its
transparent margins, rounded background and colors. `AppIcon.icns` contains all
ten standard 1x/2x representations, from 16 px through 1024 px. The bundle icon is
also used by the app's About screen.

## Regenerate

Run from the repository root. If the SVG artwork changes, first render its PNG
with an SVG renderer such as `rsvg-convert` (librsvg):

```sh
rsvg-convert -w 1024 -h 1024 \
  macos/Resources/Branding/alive-appicon-dark.svg \
  -o macos/Resources/Branding/AppIcon-1024.png
```

Then regenerate the icon using macOS's built-in `sips` and `iconutil`:

```sh
macos/scripts/generate-app-icon.sh
```

Commit the SVG, PNG and ICNS together when changing the app icon. Normal app
builds copy the committed ICNS and do not need librsvg or another new dependency.
Upstream credits, license texts and the unofficial-port notice remain in place.
