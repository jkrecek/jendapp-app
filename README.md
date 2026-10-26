# jendapp-app

iOS + macOS SwiftUI client for jendapp. The server is [jendapp-core](https://github.com/jkrecek/jendapp-core). Distributed via TestFlight only.

```sh
xcodegen                     # generates Jendapp.xcodeproj from project.yml
open Jendapp.xcodeproj
```
Targets: `Jendapp_iOS`, `Jendapp_macOS`, plus a Share extension for each (share any file → inbox → routed module). Pair a device with `jendapp pair <name>` and open the printed `jendapp://pair?...` link on it.
Signing uses `DEVELOPMENT_TEAM` in `project.yml`, which the App Group (`group.cz.frca.jendapp`) shared by the app and Share extension requires.


## Release (TestFlight)
`scripts/release.sh [ios|macos|all]` archives and uploads with the Apple ID signed in to Xcode (team 3UP4RLUQBT). Builds are numbered by timestamp, and TestFlight builds expire after 90 days. `UPLOAD=0` only exports locally.
Regenerate the icon with `swift scripts/gen-icon.swift`.
