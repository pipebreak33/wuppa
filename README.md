# Wuppa

<p align="center">
  <img src="assets/wuppa.svg" alt="Wuppa: Hej! Jag är Wuppa." width="720">
</p>

**W**hole **U**ppa **P**uppa **P**ackage. Installera Wuppa och du får hela släkten på en gång:

| | | |
|---|---|---|
| **[Uppa](https://github.com/pipebreak33/uppa)** | `uppa` | håller dina PowerShell-moduler och Microsoft-CLI:er uppdaterade |
| **[Puppa](https://github.com/pipebreak33/puppa)** | `puppa` | M365-adminuppgifter i PowerShell med några knapptryck |
| **[Muppa](https://github.com/pipebreak33/muppa)** | `muppa` | flyttar en dator från lokal AD till Entra ID: skript och checklista |
| **[Euppa](https://github.com/pipebreak33/euppa)** | `euppa` | allt i Entra ID: användare, grupper, enheter, appar, roller och villkorlig åtkomst |
| **[Ruppa](https://github.com/pipebreak33/ruppa)** | `ruppa` | appen: alla kusiner i ett fönster, med knappar och formulär |

Varje verktyg installeras med sin egen installer, så efteråt går de att köra fristående – `uppa`, `puppa`,
`muppa`, `euppa` och `ruppa` fungerar precis som om du installerat dem ett och ett.

Kommandot `wuppa` är en gemensam meny för alla: starta en kusin, se vad som kan uppdateras och uppdatera allt med
en knapp. Maskoten är ett W med ögon. Muppa och Euppa kom inte med i förkortningen, men har bästa platserna i menyn.

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
`wuppa`. Sedan kör den Uppas, Puppas, Muppas, Euppas och Ruppas egna installers, så att varje kusin hamnar precis där den annars
skulle ha hamnat (`~/.uppa`, `~/.puppa`, `~/.muppa`, `~/.euppa`, `~/.ruppa`). Går en kusin inte att installera fortsätter de andra.

| Variabel | |
|---|---|
| `WUPPA_ONLY=1` | installera bara Wuppa |
| `WUPPA_SKIP="muppa puppa"` | hoppa över kusiner |
| `WUPPA_REPO` / `WUPPA_BRANCH` | annan källa för Wuppa (kusinerna läser `UPPA_REPO`, `PUPPA_REPO` osv.) |

Från en lokal kopia: `./install.sh` / `./install.ps1`. Ligger `uppa`, `puppa`, `muppa`, `euppa` och `ruppa` utcheckade bredvid
`wuppa` installeras de därifrån.


## Avinstallera

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.sh | sh
```

Tar bort programmet och kommandot `wuppa` (och PATH-posten på Windows). Det behåller Wuppas inställningar i `~/.wuppa`.
`WUPPA_PURGE=1` tar bort även dina data, och `WUPPA_YES=1` hoppar över frågan.

Har Wuppa installerat släkten frågar avinstallationen om Uppa, Puppa, Muppa, Euppa och Ruppa ska bort också (var och en avinstalleras med sitt eget skript, deras data behålls). `WUPPA_ALL=1` svarar ja.

## Kommandon

| | |
|---|---|
| `wuppa` | menyn |
| `wuppa status` | vilka kusiner som finns och om de kan uppdateras |
| `wuppa install [uppa puppa muppa euppa ruppa]` | installera det som saknas |
| `wuppa update [uppa puppa muppa euppa ruppa]` | uppdatera det som har en nyare version, och Wuppa själv |
| `wuppa uppa …` / `wuppa puppa …` / `wuppa muppa …` / `wuppa euppa …` / `wuppa ruppa …` | kör en kusin, allt efter namnet skickas vidare |
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
