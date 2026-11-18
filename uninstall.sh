#!/usr/bin/env sh
# Avinstallera Wuppa på macOS och Linux:
#   curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.sh | sh
# Från en lokal kopia:  ./uninstall.sh
#
# Tar bort programmet (~/.wuppa/app) och kommandot ~/.local/bin/wuppa.
# Behåller Wuppas inställningar (~/.wuppa).
# WUPPA_PURGE=1 tar bort även ~/.wuppa med dina data. WUPPA_YES=1 hoppar över frågan.
# Har Wuppa installerat släkten frågar den om de ska bort också (WUPPA_ALL=1 = ja).
set -eu
START="$(date +%s)"

DIR="$HOME/.wuppa"
SHIM="$HOME/.local/bin/wuppa"

say()  { printf '  \033[38;5;220mW›\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✘\033[0m %s\n' "$1" >&2; exit 1; }

ask() {   # ask "Fråga" -> 0 om ja. Läser från terminalen även när skriptet kommer via curl | sh
  if [ -r /dev/tty ]; then
    printf '  %s [j/N] ' "$1"
    { read -r SVAR < /dev/tty; } 2>/dev/null || SVAR=""
    case "$SVAR" in j|J|ja|Ja|y|Y|yes) return 0 ;; esac
    return 1
  fi
  die "Ingen terminal att fråga i. Kör med WUPPA_YES=1 för att avinstallera utan fråga."
}

# Hela släkten? (WUPPA_ALL=1 svarar ja). Varje verktyg avinstalleras med sitt eget skript.
FAMILY=""
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
for n in uppa puppa muppa euppa ruppa; do
  case "$n" in ruppa) [ -e "${RUPPA_HOME:-$HOME/.ruppa}/bin/ruppa" ] && FAMILY="$FAMILY $n" ;;
               *) [ -e "$HOME/.local/bin/$n" ] && grep -qsF "/.$n/" "$HOME/.local/bin/$n" && FAMILY="$FAMILY $n" ;; esac
done
ALL=""
if [ -n "$FAMILY" ]; then
  if [ "${WUPPA_ALL:-}" = "1" ]; then ALL=1
  elif [ "${WUPPA_YES:-}" != "1" ] && [ -r /dev/tty ]; then
    printf '\n  Installerat av släkten:%s\n' "$FAMILY"
    ask "Ta bort dem också (deras data behålls)?" && ALL=1
  fi
fi

FOUND=""
TARGETS=""
if [ "${WUPPA_PURGE:-}" = "1" ]; then
  [ -e "$DIR" ] && { FOUND="$FOUND\n    $DIR (med dina data)"; TARGETS="$TARGETS $DIR"; }
else
  for p in app; do
    [ -e "$DIR/$p" ] && { FOUND="$FOUND\n    $DIR/$p"; TARGETS="$TARGETS $DIR/$p"; }
  done
fi
# startkommandot: bara om det är vårt (pekar på ~/.wuppa)
if [ -e "$SHIM" ] && grep -qsF "/.wuppa/" "$SHIM"; then FOUND="$FOUND\n    $SHIM"; TARGETS="$TARGETS $SHIM"; fi
if [ -z "$FOUND" ]; then
  say "Wuppa är inte installerad här. Inget att ta bort."
  exit 0
fi

printf '\n  Det här tas bort:'
printf "$FOUND\n"
[ "${WUPPA_PURGE:-}" = "1" ] || printf '  Behålls: Wuppas inställningar (~/.wuppa).\n'
printf '\n'
if [ "${WUPPA_YES:-}" != "1" ]; then
  ask "Avinstallera Wuppa?" || { say "Avbrutet. Ingenting har tagits bort."; exit 0; }
fi

FAILED=""
if [ -n "$ALL" ]; then
  TMP=""
  for n in $FAMILY; do
    printf '\n'
    up="$(printf '%s' "$n" | tr a-z A-Z)"
    if [ -n "$HERE" ] && [ -f "$HERE/../$n/uninstall.sh" ]; then
      env "${up}_YES=1" sh "$HERE/../$n/uninstall.sh" || FAILED="$FAILED $n"
    else
      [ -n "$TMP" ] || TMP="$(mktemp -d)"
      if curl -fsSL "https://raw.githubusercontent.com/pipebreak33/$n/main/uninstall.sh" -o "$TMP/$n.sh"; then
        env "${up}_YES=1" sh "$TMP/$n.sh" || FAILED="$FAILED $n"
      else
        FAILED="$FAILED $n"
      fi
    fi
  done
  [ -n "$TMP" ] && rm -rf "$TMP"
  [ -z "$FAILED" ] || printf '  \033[38;5;214m!\033[0m Gick inte att avinstallera:%s\n' "$FAILED"
fi

for t in $TARGETS; do rm -rf "$t"; done
# tom ~/.wuppa: städa bort mappen också
rmdir "$DIR" 2>/dev/null || true

SECS=$(( $(date +%s) - START ))
printf '\n  \033[38;5;42m✔\033[0m Wuppa är avinstallerad%s (%s s).\n\n' "${ALL:+, med släkten}" "$SECS"
