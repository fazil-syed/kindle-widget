# kindle-widget

A macOS desktop widget that shows your live Kindle reading progress — updated straight from the data file the Kindle app already maintains on disk. Free, local, no subscriptions.

```
NOW READING · KINDLE
Designing Data Intensive Applications
Martin Kleppmann
24.6%
━━━━░░░░░░░░░░░░
≈ page 151 of 613 · click to open · drag to move
```

## Install

Requires macOS 14+ and [Kindle for Mac 7.x](https://www.amazon.com/kindle-dbs/fd/kcp).

```sh
brew tap fazil-syed/homebrew-tap
brew install --cask fazil-syed/homebrew-tap/kindle-widget
kindle widget install
```

This installs [Übersicht](https://github.com/felixhageloh/uebersicht) automatically, adds the widget, and starts it. Drag the card to position it (position persists across restarts), click it to open Kindle at your furthest-read page. Enable **Launch at login** in Übersicht's menu-bar item.

## CLI

```sh
kindle widget install     # add the widget to Übersicht and start it
kindle widget start       # (re)start Übersicht
kindle widget data        # current reading state as JSON
kindle widget uninstall   # remove the widget (caches kept)
```

User data (drag position, page-count caches) lives in
`~/Library/Application Support/KindleWidget/` and survives upgrades.

## Building

```sh
./build.sh 0.1.0      # swiftc universal2 + tarball + sha256 for the cask
```

## License

All rights reserved — see [LICENSE](LICENSE).
