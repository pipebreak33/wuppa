# Wuppa

<p align="center">
  <img src="assets/wuppa.svg" alt="Wuppa: Hej! Jag är Wuppa." width="720">
</p>

**W**hole **U**ppa **P**uppa **P**ackage. Installera Wuppa och du får alla tre kusinerna på en gång:

| | | |
|---|---|---|
| **[Uppa](https://github.com/pipebreak33/uppa)** | `uppa` | håller dina PowerShell-moduler och Microsoft-CLI:er uppdaterade |
| **[Puppa](https://github.com/pipebreak33/puppa)** | `puppa` | M365-adminuppgifter i PowerShell med några knapptryck |
| **[Muppa](https://github.com/pipebreak33/muppa)** | `muppa` | flyttar en dator från lokal AD till Entra ID: skript och checklista |

Kommandot `wuppa` är en gemensam meny för alla tre: starta en kusin, se vad som kan uppdateras och uppdatera allt med
en knapp. Maskoten är ett W med ögon. Muppa kom inte med i förkortningen, men har bästa platsen i menyn.

## Installera (eller uppdatera allt – kör samma rad igen)

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.sh | sh
```

Installern hittar (eller på Windows installerar) Python 3.8+, lägger Wuppa i `~/.wuppa/app` och skapar kommandot
`wuppa`. Sedan kör den Uppas, Puppas och Muppas egna installers, så att varje kusin hamnar precis där den annars
skulle ha hamnat (`~/.uppa`, `~/.puppa`, `~/.muppa`). Går en kusin inte att installera fortsätter de andra.

| Variabel | |
|---|---|
| `WUPPA_ONLY=1` | installera bara Wuppa |
| `WUPPA_SKIP="muppa puppa"` | hoppa över kusiner |
| `WUPPA_REPO` / `WUPPA_BRANCH` | annan källa för Wuppa (kusinerna läser `UPPA_REPO`, `PUPPA_REPO` osv.) |

Från en lokal kopia: `./install.sh` / `./install.ps1`. Ligger `uppa`, `puppa` och `muppa` utcheckade bredvid
`wuppa` installeras de därifrån.

## Kommandon

| | |
|---|---|
| `wuppa` | menyn |
| `wuppa status` | vilka kusiner som finns och om de kan uppdateras |
| `wuppa install [uppa puppa muppa]` | installera det som saknas |
| `wuppa update [uppa puppa muppa]` | uppdatera det som har en nyare version, och Wuppa själv |
| `wuppa uppa …` / `wuppa puppa …` / `wuppa muppa …` | kör en kusin, allt efter namnet skickas vidare |
| `wuppa self-update` | uppdatera bara Wuppa |
| `--no-anim` | inga animationer (stängs också av av `NO_COLOR` och när utdata pipas) |

Menyn styrs som kusinernas: piltangenter, siffror som snabbval, `u` uppdatera allt, `i` installera det som saknas,
`r` skanna om och `q` avsluta.

## Teknik

En Python-fil (bara standardbiblioteket, 3.8+), Windows, macOS och Linux. Installerade versioner läses med
`<kusin> --version` och den senaste från `VERSION` i respektive repo på GitHub. Uppdatering kör kusinens egen
installationsrad, så Wuppa vet aldrig mer om kusinerna än de själva gör.

## Licens

MIT
