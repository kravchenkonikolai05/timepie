#!/bin/bash
# Builds TimePie.app and wraps it in TimePie-Mac.pkg, a step-by-step installer that puts
# the app in /Applications. No Xcode required.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="TimePie.app"
PKG="TimePie-Mac.pkg"
BUNDLE_ID="com.nikolaikravchenko.timepie"
VERSION="2.5.1"
BUILD="26"

echo "› building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/TimePie"

echo "› assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TimePie"

# Generated from Downloads/logo.png by iconutil; see the AppIcon.iconset folder.
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "  (no AppIcon.icns — app will use the default icon)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>TimePie</string>
    <key>CFBundleDisplayName</key>     <string>TimePie</string>
    <key>CFBundleExecutable</key>      <string>TimePie</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Ad-hoc signature — enough for the app to run on this machine.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "› packaging ${PKG}…"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root" "$WORK/scripts" "$WORK/resources"
ditto "$APP" "$WORK/root/$APP"

# Always /Applications/TimePie.app: without this, the Installer "upgrades" any copy with
# the same bundle ID it finds elsewhere (Downloads, say) instead.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"

# A clean install: quit TimePie and remove the old copy, so nothing stale survives.
# The data in ~/Library/Application Support/TimePie is left alone.
cat > "$WORK/scripts/preinstall" <<'SH'
#!/bin/sh
pkill -x TimePie || true
rm -rf /Applications/TimePie.app
exit 0
SH
chmod +x "$WORK/scripts/preinstall"

pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
  --identifier "$BUNDLE_ID" --version "$VERSION" \
  --install-location /Applications --scripts "$WORK/scripts" \
  "$WORK/TimePie.pkg" >/dev/null

cat > "$WORK/resources/welcome.html" <<HTML
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px">
<h2>TimePie $VERSION</h2>
<p>A weekly time donut: log how long you spend on each activity and see the week as a pie.</p>
<p>This puts TimePie in your Applications folder, replacing any version already there.</p>
<p>The time you've logged is kept: it lives in ~/Library/Application Support/TimePie, which installing doesn't touch.</p>
</body></html>
HTML

cat > "$WORK/resources/conclusion.html" <<HTML
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px">
<h2>TimePie is installed</h2>
<p>Open it from Launchpad, or from Applications in the Finder.</p>
</body></html>
HTML

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>TimePie</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="$(uname -m)"/>
    <domains enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="TimePie"><pkg-ref id="$BUNDLE_ID"/></choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">TimePie.pkg</pkg-ref>
</installer-gui-script>
XML

rm -f "$PKG"
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
  --package-path "$WORK" "$PKG" >/dev/null

echo "✓ $PKG"
echo "  send that file; your friend opens it and follows the installer"
echo "  run without installing: open $APP"
