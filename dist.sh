#!/bin/bash
set -e

VERSION="1.0"
DATE=$(date +%Y%m%d)
ZIPNAME="ArgusAI-${VERSION}-${DATE}.zip"

bash build.sh

rm -f "$ZIPNAME"
ditto -c -k --keepParent ArgusAI.app "$ZIPNAME"

SIZE=$(du -sh "$ZIPNAME" | cut -f1)

echo ""
echo "✓ $ZIPNAME ($SIZE)"
echo ""
echo "Istruzioni per il destinatario:"
echo "  1. Decomprimi il file"
echo "  2. Tasto destro su ArgusAI.app → Apri"
echo "  3. Clicca 'Apri' nel dialogo di sicurezza (solo la prima volta)"
echo ""
echo "  Requisiti: macOS 14+ (Sonoma), Apple Silicon, Claude Code installato"
