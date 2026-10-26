# jendapp-app

iOS + macOS SwiftUI client for jendapp. The server is [jendapp-core](https://github.com/jkrecek/jendapp-core). Distributed via TestFlight only.

```sh
xcodegen                     # generates Jendapp.xcodeproj from project.yml
open Jendapp.xcodeproj
```
Targets: `Jendapp_iOS`, `Jendapp_macOS`, plus a Share extension for each (share any file → inbox → routed module). Pair a device with `jendapp pair <name>` and open the printed `jendapp://pair?...` link on it.
Signing uses `DEVELOPMENT_TEAM` in `project.yml`, which the App Group (`group.cz.frca.jendapp`) shared by the app and Share extension requires.


## Branches & release (TestFlight)
- `dev` is where work happens. Pushing to `release` makes Xcode Cloud build iOS + macOS and send them to TestFlight internal testing:
  `git push origin dev:release`
- `ci_scripts/ci_post_clone.sh` installs XcodeGen and generates the project, because `Jendapp.xcodeproj` isn't committed. Xcode Cloud sets the build number.
- TestFlight builds expire after 90 days, so release at least that often.
- `scripts/release.sh` is a local fallback (Apple ID signed in to Xcode, team 3UP4RLUQBT). See its header for the build-number caveat.
Regenerate the icon with `swift scripts/gen-icon.swift`.
