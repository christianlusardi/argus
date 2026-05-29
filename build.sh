#!/bin/bash

# - `set -e`: manda in errore l'intero script se un comando fallisce.
# - `set -u`: considera le variabili non dichiarate come in errore
# - `set -x`: fa echo dei comandi eseguiti
# - `set -f`: disabilita il globbing (filename expansion, ovvero `*.*`). **Attenzione** che lo script non ne abbia bisogno
# - `-o pipefail`: manda in errore il comando se un comando interno ad una catena di pipe va in errore
# set -eux -o pipefail
set -eu -o pipefail

APP="ArgusAI.app"
BUNDLE="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
SDK=$(xcrun --sdk macosx --show-sdk-path)

echo "Building ArgusAI..."
mkdir -p "$BUNDLE"
mkdir -p "$RESOURCES"
cp Resources/Argus.icns "$RESOURCES/Argus.icns"

# Create Info.plist
mkdir -p "$APP/Contents"
cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ArgusAI</string>
    <key>CFBundleDisplayName</key>
    <string>ArgusAI</string>
    <key>CFBundleIdentifier</key>
    <string>com.argusai</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ArgusAI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Argus</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
EOF

SOURCES=(
    Sources/ClaudeMetrics/Theme.swift
    Sources/ClaudeMetrics/Models.swift
    Sources/ClaudeMetrics/Database.swift
    Sources/ClaudeMetrics/MetricsStore.swift
    Sources/ClaudeMetrics/Components.swift
    Sources/ClaudeMetrics/ContentView.swift
    Sources/ClaudeMetrics/OverviewView.swift
    Sources/ClaudeMetrics/ModelsView.swift
    Sources/ClaudeMetrics/ActivityView.swift
    Sources/ClaudeMetrics/ScheduleView.swift
    Sources/ClaudeMetrics/ProjectsView.swift
    Sources/ClaudeMetrics/SessionsView.swift
    Sources/ClaudeMetrics/PlatformView.swift
    Sources/ClaudeMetrics/ClaudeMetricsApp.swift
)

swiftc \
    "${SOURCES[@]}" \
    -module-name ArgusAI \
    -parse-as-library \
    -swift-version 5 \
    -target arm64-apple-macosx26.0 \
    -sdk "$SDK" \
    -framework SwiftUI \
    -framework Charts \
    -framework AppKit \
    -framework Foundation \
    -framework Combine \
    -framework Security \
    -I Sources/CSQLite \
    -lsqlite3 \
    -Onone \
    -o "$BUNDLE/ArgusAI"

codesign --force --deep --sign - "$APP"

echo "Build succeeded! Run with:"
echo "  open $APP"
echo "Or: open $(pwd)/$APP"

