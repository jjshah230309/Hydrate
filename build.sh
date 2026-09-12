#!/bin/bash
# Builds Hydrate.app — a self-contained native macOS app bundle.
# No Python, no third-party binaries, no install step.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Hydrate.app"
HELPER="$APP/Contents/Library/HydrateReminder.app"
SDK="$(xcrun --show-sdk-path)"
MIN="14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library"
mkdir -p "$HELPER/Contents/MacOS"

# ── Pick architectures: universal when the SDK can do it, else native ────────
ARCHS=("arm64" "x86_64")
probe() {
  echo 'print("ok")' > "$BUILD/.probe.swift"
  swiftc -sdk "$SDK" -target "$1-apple-macos$MIN" \
         -o "$BUILD/.probe" "$BUILD/.probe.swift" >/dev/null 2>&1
}
mkdir -p "$BUILD"
if ! probe x86_64; then
  echo "note: x86_64 slice unavailable — building for $(uname -m) only"
  ARCHS=("$(uname -m)")
fi
rm -f "$BUILD/.probe" "$BUILD/.probe.swift"

compile() {         # compile <out> <target-arch> <sources...>
  local out="$1"; shift
  local arch="$1"; shift
  swiftc -O -sdk "$SDK" -target "$arch-apple-macos$MIN" \
         -framework AppKit -framework SwiftUI -framework UserNotifications \
         -o "$out" "$@"
}

build_binary() {    # build_binary <output> <source-dir>
  local out="$1" src="$2"
  local slices=()
  for a in "${ARCHS[@]}"; do
    compile "$out.$a" "$a" "$src"/*.swift
    slices+=("$out.$a")
  done
  if [ "${#slices[@]}" -gt 1 ]; then
    lipo -create -output "$out" "${slices[@]}"
  else
    mv "${slices[0]}" "$out"
  fi
  rm -f "$out".*[0-9a-z] 2>/dev/null || true
  for a in "${ARCHS[@]}"; do rm -f "$out.$a"; done
}

echo "▸ Compiling Hydrate…"
build_binary "$APP/Contents/MacOS/Hydrate" "$ROOT/Sources/Hydrate"

echo "▸ Compiling HydrateReminder…"
build_binary "$HELPER/Contents/MacOS/HydrateReminder" "$ROOT/Sources/HydrateReminder"

# ── Resources ───────────────────────────────────────────────────────────────
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# ── Info.plists ─────────────────────────────────────────────────────────────
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Hydrate</string>
  <key>CFBundleDisplayName</key>          <string>Hydrate</string>
  <key>CFBundleIdentifier</key>           <string>com.local.hydration-tracker</string>
  <key>CFBundleExecutable</key>           <string>Hydrate</string>
  <key>CFBundleIconFile</key>             <string>AppIcon</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleVersion</key>              <string>3.0.0</string>
  <key>CFBundleShortVersionString</key>   <string>3.0.0</string>
  <key>LSMinimumSystemVersion</key>       <string>14.0</string>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>LSUIElement</key>                  <false/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Used to send hydration reminder notifications.</string>
</dict>
</plist>
PLIST

cat > "$HELPER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Hydrate Reminders</string>
  <key>CFBundleDisplayName</key>          <string>Hydrate Reminders</string>
  <key>CFBundleIdentifier</key>           <string>com.local.hydration-tracker.reminder</string>
  <key>CFBundleExecutable</key>           <string>HydrateReminder</string>
  <key>CFBundleIconFile</key>             <string>AppIcon</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleVersion</key>              <string>3.0.0</string>
  <key>CFBundleShortVersionString</key>   <string>3.0.0</string>
  <key>LSMinimumSystemVersion</key>       <string>14.0</string>
  <key>LSUIElement</key>                  <true/>
  <key>LSBackgroundOnly</key>             <false/>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Used to send hydration reminder notifications.</string>
</dict>
</plist>
PLIST

mkdir -p "$HELPER/Contents/Resources"
cp "$ROOT/Resources/AppIcon.icns" "$HELPER/Contents/Resources/AppIcon.icns"

# ── Sign (ad-hoc): inner bundle first, then the wrapper ─────────────────────
echo "▸ Signing…"
codesign --force --sign - --timestamp=none "$HELPER" >/dev/null 2>&1
codesign --force --sign - --timestamp=none "$APP"    >/dev/null 2>&1

echo "✓ Built $APP"
