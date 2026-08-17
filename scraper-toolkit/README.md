# FC26 Scraper Toolkit

4-bronnen market data scraper voor EA FC26 Ultimate Team: **FUTBIN**, **FUT.GG**, **FUTWIZ**, **FutNext**.

Status: werkend, nog niet vlekkeloos — zie "Bekende beperkingen" onderaan.

---

## Setup (eenmalig)

```powershell
npm install
```

`.env` moet minstens deze regel bevatten (los van de andere settings):
```
CHROME_PATH=C:\Program Files\Google\Chrome\Application\chrome.exe
```
Puppeteer's eigen Chrome-download werkt op sommige Windows-installaties niet betrouwbaar — daarom gebruiken we de Chrome die je toch al hebt staan. Check eerst of dat pad klopt met `Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe"`.

**Let op bij het schrijven van `.env` met PowerShell:** gebruik `Set-Content` met een here-string (`@"..."@`), niet `Add-Content` achter een bestand zonder eind-newline — anders plakken regels aan elkaar vast en werkt de env-variabele niet. Zie git-historie voor een voorbeeld van precies dit probleem.

---

## players.json vullen

`players.json` bevat de spelers die gescraped worden. Elke speler heeft een `playerId` (het EA-officiële ID — hetzelfde nummer dat in zowel de fut.gg- als de futnext-URL staat) plus de 4 volledige URL's.

**Handmatig een speler toevoegen (aanbevolen manier):**
```powershell
.\add-player.ps1
```
Vraagt interactief om naam, playerId, en de 4 URL's. Voegt netjes toe zonder dat je zelf JSON-syntax hoeft te schrijven. Draai dit script gewoon opnieuw voor elke volgende speler.

**Hoe je aan de 4 URL's + playerId komt:**
1. Zoek de speler op futbin.com → kopieer de URL (market-pagina, of gewoon de spelerpagina — wordt automatisch naar `/market` gecorrigeerd)
2. Zelfde op fut.gg, futwiz.com, futnext.com
3. Het `playerId` staat in het getal in de fut.gg-URL (`.../26-231747/`) en de futnext-URL (`.../231747`) — moet gelijk zijn

Voorbeeld-entry (schema):
```json
{
  "playerName": "Kylian Mbappé",
  "playerId": "231747",
  "urls": {
    "futbin": "https://www.futbin.com/26/player/40/kylian-mbappe/market",
    "futgg": "https://www.fut.gg/players/231747-kylian-mbappe/26-231747/",
    "futwiz": "https://www.futwiz.com/fc26/player/kylian-mbappe/33",
    "futnext": "https://www.futnext.com/player/kylian-mapp%C3%A9/231747"
  }
}
```

---

## Commando's

```powershell
node index.js                                # scrape ALLE spelers in players.json
node index.js get <playerId>                  # overzicht uit cache, ververst automatisch als > 30 min oud
node index.js get <playerId> --json            # zelfde, maar ruwe JSON i.p.v. overzicht
node index.js refresh <playerId>               # forceer volledige refresh (alle 4 bronnen)
node index.js refresh <playerId> --source=futbin   # forceer ALLEEN futbin, rest blijft uit cache
```

`MAX_AGE_MINUTES` (standaard 30) is instelbaar in `.env` — bepaalt na hoeveel minuten `get` automatisch ververst.

---

## Wat je terugkrijgt

`get <playerId>` toont standaard een leesbaar overzicht:

```
━━━ Kylian Mbappé — Gold Rare ━━━
Rating: 91  Position: ST  Club: Real Madrid  Nation: France

BIN prices:
  FUTBIN:  68000
  FUT.GG:  63500
  FUTWIZ:  65000
  FutNext: 65000
  Average: 65375
  Cheapest right now: 63500 op futgg
  Price range (FUTBIN): 4400 - 85000 (currently at 74.9% of range)
  Trend: 16.24% (+9.5K)
  FUTBIN top-5 lowest: 68000, 69000, 70000, 71000, 72000

Recent sales (FUTBIN):
  Aug 16, 9:19 AM — 60K
  ...

Scraped in 4823ms (futbin 2341ms, futgg 1204ms, futwiz 1876ms, futnext 921ms)
Last updated: 2026-08-16T...
```

**Belangrijk:** als de kaartversie tussen bronnen niet overeenkomt (bijv. FUTBIN zegt "Gold Rare" maar FUT.GG zegt "TOTW" — teken dat de URL's niet naar dezelfde kaart wijzen), verschijnt bovenaan een `⚠️ Card version MISMATCH`-regel.

### Velden in het `merged` object (via `--json`)

| Veld | Betekenis |
|---|---|
| `binPrices.{futbin,futgg,futwiz,futnext}` | BIN-prijs per bron |
| `lowestAcrossSources` | `{source, price}` — waar nú het goedkoopst |
| `averageBinPrice` | Gemiddelde van alle beschikbare bronnen |
| `priceRange` / `binPricePercentInRange` | FUTBIN's historische range + waar de huidige prijs daarbinnen zit (0% = bodem, 100% = piek) |
| `futbinLowest5` / `futbinLowest5Count` | Tot 5 laagste actuele listings op FUTBIN (site toont niet altijd 5 unieke) |
| `recentSales` | FUTBIN's "Latest Sales"-mini-lijst (datum + bedrag) |
| `recentSalesFutgg` / `liveAuctionsFutgg` | **Experimenteel**, zie beperkingen |
| `cardVersion` (top-level) + `versionCheck` | Kaartversie + of alle bronnen het eens zijn |
| `timing` (top-level) | Duur per bron + totaal, in ms |

---

## Logs & opslag

| Bestand | Inhoud |
|---|---|
| `output/cards.json` | Snapshot van de laatste volledige `node index.js`-run (alle spelers) |
| `output/players-db.json` | Persistente cache per `playerId` — dit is de "database" die `get`/`refresh` gebruiken |
| `output/scrape-timings.log` | JSONL, 1 regel per scrape-run: tijdsduur per bron + welke bronnen slaagden. Handig om te zien welke bron structureel traag/onbetrouwbaar is |

---

## Bekende beperkingen (eerlijk overzicht, wordt bijgewerkt)

- **FUT.GG Recent Sales / Live Auctions is experimenteel.** Bevestigd via directe HTML-fetch dat deze content niet eens als lege skeleton in de server-HTML staat — hij wordt puur client-side gebouwd, mogelijk pas na scrollen/interactie. De scraper probeert dit best-effort (scrollt naar `#prices`, wacht, checkt op de tekst "Recent Sales"/"Live Auctions"), maar kan leeg terugkomen zonder dat dit een bug is. Als dit structureel leeg blijft: stuur een DevTools element-picker screenshot van die sectie (zelfde methode als voor de BIN-prijs-selectors) zodat we 'm hard kunnen maken.
- **FUTBIN `recentSales` is de mini-lijst op de market-pagina zelf**, niet de volledige sales-geschiedenis met EA-tax-breakdown (die staat op een aparte `/sales/{id}/{slug}?platform=ps`-pagina en zou een extra paginabezoek per speler kosten — kan later toegevoegd worden als gewenst).
- **`cardVersion`-extractie is regex-gebaseerd** op breadcrumbs/titels/velden per site. Werkt betrouwbaar voor standaardkaarten (Gold Rare); bij exotischere versies (TOTY Honorable Mentions, Icon, Hero) kan het patroon net anders zijn — check de `versionCheck`-waarschuwing als je twijfelt, en meld het als een kaartversie er raar uitziet.
- **Sitestructuur kan wijzigen.** Alle selectors zijn op een specifiek moment (16 augustus 2026) via DevTools geverifieerd. Als een site zijn HTML/CSS-classes update, kan een veld plots `null` teruggeven — dat is dan geen scraper-crash maar een teken dat de selector opnieuw geverifieerd moet worden.
- **Chrome moet lokaal geïnstalleerd staan** (via `CHROME_PATH` in `.env`) — Puppeteer's eigen download bleek onbetrouwbaar op dit systeem.

---

## Troubleshooting

| Probleem | Oorzaak | Fix |
|---|---|---|
| `Could not find Chrome` | `CHROME_PATH` ontbreekt of `.env` is corrupt (regels aan elkaar geplakt) | `Get-Content .env` checken, zie Setup-sectie |
| `Cannot read properties of undefined (reading 'futbin')` | `players.json` heeft nog het oude schema (zonder `urls`) | `Remove-Item players.json` + apply-script opnieuw draaien (schrijft verse starter-file) |
| `playerId niet found in players.json` | Player nog niet toegevoegd, of `playerId` komt niet exact overeen | `.\add-player.ps1` gebruiken, of `Get-Content players.json` checken |
| Git "dubious ownership" | Externe schijf (D:) wordt niet vertrouwd door git | `git config --global --add safe.directory D:/Projects/mat-26` |
| `git push` rejected | Remote heeft al commits die je lokaal niet hebt | `git pull origin main --allow-unrelated-histories` |

