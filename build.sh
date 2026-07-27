#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="DiskSweeper.app"
BIN="DiskSweeper"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>DiskSweeper</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.rajeshsood.disksweeper</string>
	<key>CFBundleName</key>
	<string>DiskSweeper</string>
	<key>CFBundleDisplayName</key>
	<string>DiskSweeper</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Rajesh Sood</string>
</dict>
</plist>
PLIST

# --- App icon: render from an SF Symbol (stays crisp at every size, no text) ---
ICON_SCRIPT="$(mktemp /tmp/rendericon-XXXX).swift"
cat > "$ICON_SCRIPT" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.28, alpha: 1),
           ending: NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.08, alpha: 1))?
    .draw(in: bgRect, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config),
   let cg = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil),
   let ctx = NSGraphicsContext.current?.cgContext {
    let symSize = symbol.size
    let rect = CGRect(x: (size - symSize.width) / 2, y: (size - symSize.height) / 2,
                       width: symSize.width, height: symSize.height)
    ctx.saveGState()
    ctx.clip(to: rect, mask: cg)
    NSColor.white.setFill()
    ctx.fill(rect)
    ctx.restoreGState()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

SQ="$(mktemp /tmp/appicon-XXXX).png"
swift "$ICON_SCRIPT" "$SQ"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SQ" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$SQ" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
echo "Icon:  AppIcon.icns rendered from SF Symbol"

SOURCES=$(find Sources -name '*.swift')

# SwiftUI @main requires -parse-as-library.
swiftc -O -parse-as-library \
  -o "$APP/Contents/MacOS/$BIN" \
  $SOURCES

echo "Built $APP"

# --- Install to /Applications ---
DEST="/Applications/$APP"
if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
if ditto "$APP" "$DEST" 2>/dev/null; then
  echo "Installed to $DEST"
  echo "Run:  open \"$DEST\""
else
  echo "WARN: could not write to /Applications (permissions?). Retrying with sudo…"
  sudo rm -rf "$DEST" && sudo ditto "$APP" "$DEST" && echo "Installed to $DEST (sudo)"
fi
