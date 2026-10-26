#!/bin/sh
# Archive and upload Jendapp to App Store Connect (TestFlight).
#
#   scripts/release.sh            # iOS + macOS, upload
#   scripts/release.sh ios        # one platform
#   UPLOAD=0 scripts/release.sh   # archive + export locally only (signing check)
#
# Uses the Apple ID signed in to Xcode (-allowProvisioningUpdates); no API keys.
# TestFlight builds expire after 90 days — rerun this before then.
set -eu
cd "$(dirname "$0")/.."

PLATFORMS=${1:-all}
UPLOAD=${UPLOAD:-1}
TEAM=3UP4RLUQBT
BUILD=$(date +%Y%m%d%H%M) # monotonically increasing CFBundleVersion
OUT=.build-release/$BUILD
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

xcodegen -q
mkdir -p "$OUT"

DEST=export
[ "$UPLOAD" = 1 ] && DEST=upload
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DEST</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
EOF

release() { # $1 = iOS | macOS
	archive="$OUT/Jendapp-$1.xcarchive"
	echo "==> $1: archiving build $BUILD"
	xcodebuild -quiet -project Jendapp.xcodeproj -scheme "Jendapp_$1" -configuration Release \
		-destination "generic/platform=$1" -archivePath "$archive" \
		-allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive
	echo "==> $1: exporting ($DEST)"
	xcodebuild -quiet -exportArchive -archivePath "$archive" -exportPath "$OUT/$1" \
		-exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
}

case "$PLATFORMS" in
	ios) release iOS ;;
	macos) release macOS ;;
	all) release iOS; release macOS ;;
	*) echo "usage: $0 [ios|macos|all]" >&2; exit 2 ;;
esac
echo "==> done: build $BUILD ($DEST)"
