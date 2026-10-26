# Brand assets

`AyrvoIcon.png` is the approved master: folded blue and purple planes on a dark
navy tile, with transparency outside the tile. Keep this source unchanged when
regenerating the app icon.

- `AppIcon-1024.png` and `AppIcon.icns` are derived from the master with `make app-icon`.
- The menu bar uses a simplified, monochrome silhouette drawn by
  `scripts/MakeIcon.swift`. Regenerate its 1× and 2× PNGs with `make nav-icon`.
  The app loads these as template images so macOS supplies the appropriate color.

The shared `AyrvoMark` SwiftUI view uses the app bundle's native icon rather than
loading another copy of the master into each view.
