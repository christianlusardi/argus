#!/bin/bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ── Version ───────────────────────────────────────────────────────────
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    printf "Versione da rilasciare (es. 1.2.0): "
    read -r VERSION
fi
[[ -z "$VERSION" ]] && err "Versione non specificata."
[[ "$VERSION" != v* ]] && VERSION="v$VERSION"

TAG="$VERSION"
DATE=$(date +%Y%m%d)
APP="ArgusAI.app"
ZIPNAME="ArgusAI-${TAG}-${DATE}.zip"

echo ""
echo -e "${BOLD}ArgusAI Release Script — ${TAG}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Flight Checklist ─────────────────────────────────────────────────
step "Flight checklist"

# 1. swiftc / Xcode CLT
if ! command -v swiftc &>/dev/null; then
    err "swiftc non trovato. Installa Xcode Command Line Tools:\n  xcode-select --install"
fi
ok "swiftc: $(swiftc --version 2>&1 | head -1)"

# 2. git
command -v git &>/dev/null || err "git non trovato."
ok "git: $(git --version | awk '{print $3}')"

# 3. codesign
command -v codesign &>/dev/null || err "codesign non trovato. Installa Xcode Command Line Tools."
ok "codesign"

# 4. ditto (sempre presente su macOS)
command -v ditto &>/dev/null || err "ditto non trovato."
ok "ditto"

# 5. shasum
command -v shasum &>/dev/null || err "shasum non trovato."
ok "shasum"

# 6. Homebrew (necessario per installare gh)
if ! command -v brew &>/dev/null; then
    warn "Homebrew non trovato. Lo installo ora..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Aggiunge brew al PATH per questa sessione (Apple Silicon)
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
    ok "Homebrew installato"
else
    ok "brew: $(brew --version | head -1)"
fi

# 7. gh CLI
if ! command -v gh &>/dev/null; then
    echo -e "  ${YELLOW}→${NC} gh non trovato. Installo via Homebrew..."
    brew install gh
    ok "gh installato"
else
    ok "gh: $(gh --version | head -1 | awk '{print $3}')"
fi

# 8. gh auth
if ! gh auth status &>/dev/null; then
    warn "gh non autenticato. Avvio il login..."
    gh auth login
fi
ok "gh autenticato ($(gh api user -q .login))"

# 9. remote origin
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
[[ -z "$REMOTE_URL" ]] && err "Nessun remote 'origin' configurato."
ok "remote: $REMOTE_URL"

# 10. branch sincronizzato
git fetch origin --quiet 2>/dev/null || warn "Impossibile fare fetch — procedo comunque."
BEHIND=$(git rev-list --count HEAD..origin/$(git rev-parse --abbrev-ref HEAD) 2>/dev/null || echo 0)
if [[ "$BEHIND" -gt 0 ]]; then
    warn "Il branch locale è $BEHIND commit indietro rispetto a origin. Considera un pull."
fi

# 11. modifiche non committate
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    warn "Ci sono modifiche non committate (non verranno incluse nel tag)."
fi

# 12. tag non già esistente
if git rev-parse "$TAG" &>/dev/null 2>&1; then
    err "Il tag $TAG esiste già.\nPer eliminarlo: git tag -d $TAG && git push origin :refs/tags/$TAG"
fi
ok "tag $TAG disponibile"

echo ""
echo -e "  ${BOLD}Tutto ok. Procedo con la release ${TAG}.${NC}"

# ── Build ─────────────────────────────────────────────────────────────
step "Build"
bash build.sh
ok "$APP compilato e firmato (ad-hoc)"

# ── Zip ──────────────────────────────────────────────────────────────
step "Pacchetto"
rm -f "$ZIPNAME"
ditto -c -k --keepParent "$APP" "$ZIPNAME"
SIZE=$(du -sh "$ZIPNAME" | cut -f1)
ok "Creato $ZIPNAME ($SIZE)"

# ── Fingerprint ──────────────────────────────────────────────────────
step "Fingerprint"
SHA256=$(shasum -a 256 "$ZIPNAME" | awk '{print $1}')
MD5=$(md5 -q "$ZIPNAME")
ok "SHA256: $SHA256"
ok "MD5:    $MD5"

# Salva anche in un file .sha256 nella stessa cartella (opzionale, non incluso nel release)
echo "$SHA256  $ZIPNAME" > "${ZIPNAME}.sha256"

# ── Tag & push ───────────────────────────────────────────────────────
step "Tag Git"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
ok "Tag $TAG pushato su origin"

# ── Changelog automatico ─────────────────────────────────────────────
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)
if [[ -n "$PREV_TAG" ]]; then
    CHANGELOG=$(git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" 2>/dev/null)
    CHANGELOG_HEADER="### Changelog (da \`${PREV_TAG}\`)"
else
    CHANGELOG=$(git log --pretty=format:"- %s" 2>/dev/null | head -20)
    CHANGELOG_HEADER="### Commits inclusi"
fi

# ── Release notes ────────────────────────────────────────────────────
NOTES="## ArgusAI ${TAG}

Monitor nativo macOS per Claude Code usage metrics — dark theme, Liquid Glass UI (macOS 26), menu bar extra.

### Requisiti
- macOS 14+ (Sonoma) — ottimizzato per macOS 26 con Liquid Glass
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) installato (\`~/.claude/projects/\` deve esistere)

### Installazione
1. Scarica \`${ZIPNAME}\` qui sotto
2. Decomprimi il file
3. **Tasto destro** su \`ArgusAI.app\` → **Apri**
4. Clicca **Apri** nel dialogo di sicurezza macOS (solo la prima volta)

> ℹ️ L'app usa firma ad-hoc (non Apple Developer ID). Il dialogo Gatekeeper è normale.

---

### Integrità del file

Verifica il download prima di aprirlo:

\`\`\`bash
shasum -a 256 ${ZIPNAME}
# atteso: ${SHA256}

md5 ${ZIPNAME}
# atteso: ${MD5}
\`\`\`

| Algoritmo | Hash |
|-----------|------|
| SHA256 | \`${SHA256}\` |
| MD5 | \`${MD5}\` |

---

${CHANGELOG_HEADER}
${CHANGELOG}"

# ── GitHub Release ───────────────────────────────────────────────────
step "GitHub Release"
gh release create "$TAG" "$ZIPNAME" \
    --title "ArgusAI ${TAG}" \
    --notes "$NOTES" \
    --latest

RELEASE_URL=$(gh release view "$TAG" --json url -q .url)
ok "Release pubblicata: $RELEASE_URL"

# ── Riepilogo ────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}  Release ${TAG} completata!${NC}"
echo ""
echo -e "  URL     ${RELEASE_URL}"
echo -e "  Asset   ${ZIPNAME} (${SIZE})"
echo -e "  SHA256  ${SHA256}"
echo -e "  MD5     ${MD5}"
echo ""
echo -e "  Per verificare: gh release view ${TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
