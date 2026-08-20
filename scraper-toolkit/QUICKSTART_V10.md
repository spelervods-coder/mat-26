# MAT-26 v10 — Snelle Gebruiksinstructie

## Installatie

```powershell
cd D:\Projects\mat-26\scraper-toolkit
.\apply-fixes-v10.ps1
```

**Optioneel** (aanbevolen), toevoegen aan `.env`:
```
ACCOUNT_BUDGET=500000
RISK_PROFILE=standard
```
`RISK_PROFILE` = `conservative` | `standard` | `aggressive`.

---

## Dagelijkse workflow — human-in-the-loop

Jij handelt in-game, het systeem logt en adviseert via één kort commando per stap. Niets hierin raakt je EA-account — alles is een aanbeveling, jij voert het zelf uit.

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐
│  1. buy     │ --> │  2. list      │ --> │ 3a. sold      │  (klaar)
└─────────────┘     └──────────────┘     └───────────────┘
                                                  │
                                                  ▼ (niet verkocht binnen 60 min)
                                          ┌───────────────┐
                                          │ 3b. expired   │ --> geeft nieuwe relist-prijs
                                          └───────────────┘
                                                  │
                                                  ▼
                                          ┌───────────────┐
                                          │  4. relist    │ --> terug naar 3a/3b
                                          └───────────────┘
                                          (max 3x, daarna "stuck")
```

### Commando's

```powershell
node index.js buy <cardId> <prijs>
# Logt aankoop, toont meteen aanbevolen verkoopprijs + TOS-score + slot-status

node index.js list <positionId> <prijs>
# Logt dat je 'm gelist hebt (60 min)

node index.js sold <positionId> <prijs>
# Logt verkoop, sluit de positie, toont winst

node index.js expired <positionId>
# Logt niet-verkocht, haalt verse data op, geeft NIEUWE relist-prijs
# (herberekend, geen vast kortingspercentage)

node index.js relist <positionId> <prijs>
node index.js positions
# Dashboard: alle open posities + hoeveel van de 100 slots bezet
```

**Tip:** `positionId` mag afgekort — de eerste 8 tekens die na `buy` getoond worden zijn genoeg.

### Voorbeeld

```powershell
> node index.js buy 231747 58000
✅ BUY gelogd: Kylian Mbappé voor 58000
   Position ID: a3f9c21e-...  (kort: a3f9c21e)

💡 Aanbevolen verkoopprijs: 63500
   Verwachte winst: 2525  |  ROI: 4.4%  |  TOS: 6.6/10
   Actieve slots: 12/100  |  Van dit kaarttype: 1

Volgende stap: node index.js list a3f9c21e <prijs>

> node index.js list a3f9c21e 63500
✅ LIST gelogd: Kylian Mbappé voor 63500 (60 min)

# ... 60 minuten later, niet verkocht ...

> node index.js expired a3f9c21e
⏰ EXPIRE gelogd: Kylian Mbappé
   Let op: EA plaatst dit NIET automatisch terug in je club.
   Verse data ophalen voor relist-advies...

💡 Nieuwe relist-prijs: 62000 (was 63500)
Volgende stap: node index.js relist a3f9c21e 62000

> node index.js relist a3f9c21e 62000
✅ RELIST #1 gelogd: Kylian Mbappé voor 62000

> node index.js sold a3f9c21e 62000
✅ SOLD gelogd: Kylian Mbappé voor 62000 (netto 58900)
💰 Winst: +900
```

---

## players.json vullen (herhaling)

```powershell
.\add-player.ps1        # 1 speler per keer, 4 URL's + optioneel naam/Card ID
.\manage-players.ps1    # menu: lijst / bewerken / verwijderen
```

## Data verzamelen (voor 10-20 spelers)

```powershell
node index.js                    # scrape alles, vult players-db.json + price-history.jsonl
.\scheduler.ps1                  # in een APART venster: herhaalt dit elke N minuten
```

## Eén speler snel checken

```powershell
node index.js get <cardId>                          # uit cache, auto-ververst als >30min oud
node index.js refresh <cardId> --prices-only         # snel, zonder sales-history
```

---

## Wat nog ontbreekt (bewust, voor later)

- TOS-gewichten (35/30/20/15%) zijn nog ongekalibreerd — pas herijken na 20-30 gesloten posities (`node index.js positions` toont dit aantal)
- Geen webdashboard, alleen CLI — `node index.js positions` is voorlopig het overzicht
- `RISK_PROFILE` is nu globaal, niet per kaart
