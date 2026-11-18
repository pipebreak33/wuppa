#!/usr/bin/env sh
# Wuppa för macOS och Linux – installerar Wuppa och kusinerna Uppa, Puppa, Muppa, Euppa och Ruppa.
# Kör samma rad igen = allt uppdateras till senaste versionen:
#   curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.sh | sh
# Från en lokal kopia:  ./install.sh   (finns ../uppa, ../puppa, ../muppa, ../euppa, ../ruppa bredvid används de också)
# Styr källan med WUPPA_REPO=ägare/repo och WUPPA_BRANCH=gren. Kusinerna läser UPPA_REPO, PUPPA_REPO osv.
# WUPPA_ONLY=1 installerar bara Wuppa. WUPPA_SKIP="muppa puppa" hoppar över kusiner.
set -eu
START="$(date +%s)"

REPO="${WUPPA_REPO:-pipebreak33/wuppa}"
BRANCH="${WUPPA_BRANCH:-main}"
OWNER="${REPO%%/*}"
DIR="$HOME/.wuppa"
APP="$DIR/app"
BIN="$HOME/.local/bin"

say()  { printf '  \033[38;5;220mW›\033[0m %s\n' "$1"; }
warn() { printf '  \033[38;5;214m!\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✘\033[0m %s\n' "$1" >&2; exit 1; }

# 1. Python 3.8+ (Wuppa och kusinerna är Python-skript utan beroenden)
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
    PY="$(command -v "$c")"; break
  fi
done
if [ -z "$PY" ]; then
  case "$(uname -s)" in
    Darwin) die "Python 3.8+ saknas. Kör: xcode-select --install   (eller: brew install python)";;
    *)      die "Python 3.8+ saknas. Kör: sudo apt install python3   (eller dnf/pacman motsvarande)";;
  esac
fi

# 2. Källan: en lokal checkout bredvid skriptet, annars arkivet från GitHub
SRC=""
LOCAL=""
case "$0" in
  *install.sh)
    HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
    if [ -n "$HERE" ] && [ -f "$HERE/wuppa.py" ] && [ "${WUPPA_FROM_WEB:-}" != "1" ]; then
      SRC="$HERE"; LOCAL="$HERE"
      say "Installerar från $HERE"
    fi;;
esac
TMP=""
cleanup() { if [ -n "$TMP" ]; then rm -rf "$TMP"; fi; return 0; }
trap cleanup EXIT
if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "curl saknas."
  command -v tar >/dev/null 2>&1 || die "tar saknas."
  TMP="$(mktemp -d)"
  say "Hämtar Wuppa från github.com/$REPO ($BRANCH)"
  curl -fsSL "https://github.com/$REPO/archive/$BRANCH.tar.gz" -o "$TMP/wuppa.tar.gz" \
    || die "nedladdningen misslyckades – kolla nätet eller WUPPA_REPO/WUPPA_BRANCH"
  tar -xzf "$TMP/wuppa.tar.gz" -C "$TMP" || die "kunde inte packa upp arkivet"
  SRC="$(find "$TMP" -maxdepth 2 -name wuppa.py -exec dirname {} \; | head -n 1)"
  [ -n "$SRC" ] || die "arkivet innehåller inte Wuppa"
fi
"$PY" -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$SRC/wuppa.py" \
  || die "wuppa.py är trasig"

# 3. Byt ut programmet (~/.wuppa/app)
mkdir -p "$DIR" "$BIN"
rm -rf "$APP.new"
mkdir -p "$APP.new"
cp "$SRC/wuppa.py" "$APP.new/wuppa.py"
for f in README.md LICENSE; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$APP.new/$f"; done
rm -rf "$APP"
mv "$APP.new" "$APP"

# 4. Startkommando i ~/.local/bin (en ev. gammal symlänk tas bort först – skriv aldrig genom den)
rm -f "$BIN/wuppa"
cat > "$BIN/wuppa" <<SHIM
#!/usr/bin/env sh
exec "$PY" "$APP/wuppa.py" "\$@"
SHIM
chmod +x "$BIN/wuppa"

# 5. ~/.local/bin i PATH
case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    case "${SHELL:-}" in
      */zsh)  RC="$HOME/.zshrc" ;;
      */bash) RC="$HOME/.bashrc"; [ "$(uname -s)" = Darwin ] && RC="$HOME/.bash_profile" ;;
      *)      RC="$HOME/.profile" ;;
    esac
    grep -qs '.local/bin' "$RC" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
    say "La till ~/.local/bin i PATH ($RC). Öppna en ny terminal."
    ;;
esac
VER="$("$PY" "$APP/wuppa.py" --version 2>/dev/null || echo wuppa)"
printf '  \033[38;5;42m✔\033[0m %s installerad.\n' "$VER"

# 6. Kusinerna: kör var och ens egen installer (installerar eller uppdaterar)
FAILED=""
if [ "${WUPPA_ONLY:-}" != "1" ]; then
  export RUPPA_NO_OPEN=1          # Ruppa: öppna inte appen mitt i installationen
  for name in uppa puppa muppa euppa ruppa; do
    case " ${WUPPA_SKIP:-} " in *" $name "*) continue;; esac
    printf '\n'
    if [ -n "$LOCAL" ] && [ -f "$LOCAL/../$name/install.sh" ] && \
       { [ -f "$LOCAL/../$name/$name.py" ] || [ -f "$LOCAL/../$name/Cargo.toml" ]; }; then
      say "$name från $(cd "$LOCAL/../$name" && pwd)"
      sh "$LOCAL/../$name/install.sh" || FAILED="$FAILED $name"
    else
      say "$name från github.com/$OWNER/$name"
      [ -n "$TMP" ] || TMP="$(mktemp -d)"
      # Ladda ner först: med "curl | sh" skulle ett nätfel se ut som en lyckad installation
      if curl -fsSL "https://raw.githubusercontent.com/$OWNER/$name/main/install.sh" -o "$TMP/$name-setup.sh"; then
        sh "$TMP/$name-setup.sh" || FAILED="$FAILED $name"
      else
        warn "kunde inte hämta $name"; FAILED="$FAILED $name"
      fi
    fi
  done
fi

printf '\n'
SECS=$(( $(date +%s) - START )); if [ "$SECS" -ge 60 ]; then TOOK="$((SECS / 60)) min $((SECS % 60)) s"; else TOOK="$SECS s"; fi
if [ -n "$FAILED" ]; then
  warn "Det här gick inte:$FAILED ($TOOK). Kör samma rad igen om en stund, eller: wuppa install$FAILED"
  printf '  Resten är klart. Kör: \033[1mwuppa\033[0m\n\n'
  exit 1
fi
printf '  \033[38;5;220mW›\033[0m Klart på %s! Kör \033[1mwuppa\033[0m för menyn, eller uppa, puppa, muppa, euppa och ruppa direkt.\n' "$TOOK"
printf '  \033[2mAvinstallera: curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.sh | sh   (frågar om hela släkten)\033[0m\n\n'
