# FC26 Scraper Toolkit

**4-Source Market Data Scraper** for EA FC26 Ultimate Team

## Sources
- FUTBIN.com (prices, trends)
- FUT.GG (ratings, meta)
- FUTWIZ.com (market values)
- FutNext.com (pack odds)

## Setup

```bash
npm install
cp .env.example .env
node index.js "Mbappe"
```

## Commands

```bash
npm start                 # Scrape all sources
npm run scrape:futbin     # FUTBIN only
npm run scrape:futgg      # FUT.GG only
npm run scrape:futwiz     # FUTWIZ only
npm run scrape:futnext    # FutNext only
```

## Output

Result: `cards.json` (merged data from all 4 sources)

```json
{
  "players": [
    {
      "playerName": "Mbappe",
      "cardId": "123456",
      "futbin": { "price": 72000, "trend": "+5.11%" },
      "futgg": { "rating": 91, "updated": "2024-08-14T14:30Z" },
      "futwiz": { "marketValue": 72500, "range": "70K-75K" },
      "futnext": { "packOdds": 0.0012 }
    }
  ]
}
```

## Risks

⚠️ Web scraping may violate ToS. Use responsibly.
- Stealth plugin enabled
- Request delays (1s default)
- Rotate User-Agents
- Scrape off-peak hours

## License

MIT