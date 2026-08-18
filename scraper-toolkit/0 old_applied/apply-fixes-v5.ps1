# apply-fixes-v5.ps1
# Adds: per-source + total timing (logged to output/scrape-timings.log),
# lowestPricesCount transparency field, and a fully updated README.md.
# Auto-commits + pushes to git at the end.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v5 files..." -ForegroundColor Cyan

$content_futbin_scraper_js = @'
/**
 * FUTBIN SCRAPER (v4)
 *
 * NEW:
 * - cardVersion: parsed from the breadcrumb ("... > Players > Kylian
 *   Mbappé Gold Rare") - the text after the player's name on that line.
 * - recentSales: reuses the "Latest Sales" mini-list already present on
 *   this same market page (.xs-column.full-width) - date + amount pairs.
 *   NOT the full EA-tax-breakdown sales history table (that lives on a
 *   separate /sales/ page - can be added later if useful, costs an extra
 *   page load per player).
 *
 * FIXED:
 * - priceRange/priceUpdated were returning null in practice because the
 *   .price-box-full-width-xxs-column selector wasn't reliably matching.
 *   Switched to body-innerText regex on the literal "PRICE RANGE:" /
 *   "PRICE UPDATED:" labels instead - same approach that already worked
 *   for trend/market-grid extraction.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, rawUrl) {
  console.log(`  📊 FUTBIN: Scraping "${playerName}"...`);

  let browser;
  try {
    let url = rawUrl.replace(/\/+$/, '');
    if (!url.endsWith('/market')) url += '/market';

    browser = await puppeteer.launch({
      headless: process.env.HEADLESS !== 'false',
      executablePath: process.env.CHROME_PATH || undefined,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    });

    const page = await browser.newPage();
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    );

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 20000 });
    await page.waitForSelector('.price.inline-with-icon.lowest-price-1', { timeout: 15000 });

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };
      const clean = (t) => t?.replace(/\s+/g, ' ').trim() || null;

      const lowestPrice = num(document.querySelector('.price.inline-with-icon.lowest-price-1')?.textContent);

      function extractPrices(container) {
        if (!container) return [];
        const leafEls = Array.from(container.querySelectorAll('*')).filter(el => el.children.length === 0);
        const candidates = leafEls.length ? leafEls : Array.from(container.children);
        return candidates.map(el => num(el.textContent)).filter(n => n !== null);
      }
      let lowestPrices = extractPrices(document.querySelector('.lowest-prices-wrapper'));
      if (lowestPrice !== null && lowestPrices[0] !== lowestPrice) lowestPrices.unshift(lowestPrice);
      lowestPrices = lowestPrices.slice(0, 5);
      const lowestPricesCount = lowestPrices.length; // site doesn't always show all 5

      const bodyText = document.body.innerText;

      // FIXED: body-text regex instead of broken selector
      const rangeMatch = bodyText.match(/PRICE RANGE:\s*\n?\s*([\d,]+)\s*-\s*([\d,]+)/i);
      const priceRange = rangeMatch ? { min: num(rangeMatch[1]), max: num(rangeMatch[2]) } : null;
      const updatedMatch = bodyText.match(/PRICE UPDATED:\s*([^\n]+)/i);
      const priceUpdated = updatedMatch ? clean(updatedMatch[1]) : null;

      const avgBinMatch = bodyText.match(/Average BIN\s*\n?\s*([\d,]+)/i);
      const cheapestMatch = bodyText.match(/Cheapest Sale\s*\n?\s*(?:[A-Za-z]{3}\s*\d+,?\s*[\d:APM\s]*\n?\s*)?([\d,]+)/i);
      const eaAvgMatch = bodyText.match(/EA Avg\.?\s*Price\s*\n?\s*([\d,]+)/i);

      const trendMatch = bodyText.match(/Trend:\s*([\-\d.]+%\s*\([^)]+\))/i);

      // Card version - from the breadcrumb line: "... > Players > <Name> <Version>"
      const breadcrumbMatch = bodyText.match(/Players\s*>\s*[^\n]+/i);
      let cardVersion = null;
      if (breadcrumbMatch) {
        const line = breadcrumbMatch[0];
        // strip "Players > " and the player's name, keep trailing words as version
        const afterPlayers = line.replace(/^Players\s*>\s*/i, '').trim();
        const words = afterPlayers.split(/\s+/);
        // heuristic: version is usually the last 1-3 words (e.g. "Gold Rare", "TOTW", "TOTY Honorable Mentions")
        cardVersion = words.slice(-3).join(' ');
      }
      if (!cardVersion) {
        const titleMatch = document.title.match(/[\u2013-]\s*(.+?)\s*EA FC/i);
        cardVersion = titleMatch ? titleMatch[1].trim() : null;
      }

      // Recent sales mini-list (same page, "Latest Sales" panel)
      const salesContainer = Array.from(document.querySelectorAll('*')).find(
        el => el.children.length === 0 && el.textContent.trim() === 'Latest Sales'
      )?.closest('div')?.parentElement;
      let recentSales = [];
      if (salesContainer) {
        const rows = Array.from(salesContainer.querySelectorAll('.xs-column.full-width'));
        recentSales = rows
          .map(el => clean(el.textContent))
          .filter(Boolean)
          .map(text => {
            const m = text.match(/^(.+?\d{1,2}:\d{2}\s*[AP]M)\s*([\d,.]+K?)/i);
            return m ? { when: m[1].trim(), amount: m[2].trim() } : { raw: text };
          });
      }

      return {
        lowestPrice,
        lowestPrices,
        lowestPricesCount,
        priceRange,
        priceUpdated,
        averageBin: avgBinMatch ? num(avgBinMatch[1]) : null,
        cheapestSale: cheapestMatch ? num(cheapestMatch[1]) : null,
        eaAveragePrice: eaAvgMatch ? num(eaAvgMatch[1]) : null,
        trend: trendMatch ? trendMatch[1].trim() : null,
        cardVersion,
        recentSales,
      };
    });

    const result = { source: 'FUTBIN', ...data, url, timestamp: new Date().toISOString() };
    console.log(`    ✅ FUTBIN:`, result);
    return result;

  } catch (error) {
    console.error(`    ❌ FUTBIN Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };

'@
Set-Content -Path ".\futbin-scraper.js" -Value $content_futbin_scraper_js -NoNewline
Write-Host "  wrote futbin-scraper.js" -ForegroundColor Green

$content_index_js = @'
/**
 * FC26 SCRAPER ORCHESTRATOR (v5)
 *
 * NEW: per-source + total timing, logged to console AND appended to
 * output/scrape-timings.log (JSONL - one line per scrape run) so you can
 * see over time which source is slow or flaky.
 *
 * Usage:
 *   node index.js                              scrape ALL players.json entries
 *   node index.js get <playerId>                pretty overview (from cache, auto-refresh if stale)
 *   node index.js get <playerId> --json          same, but raw JSON instead of the overview
 *   node index.js refresh <playerId>             force full refresh (all 4 sources)
 *   node index.js refresh <playerId> --source=futbin   refresh only 1 source
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');

const futbinScraper = require('./futbin-scraper');
const futggScraper = require('./futgg-scraper');
const futwizScraper = require('./futwiz-scraper');
const futnextScraper = require('./futnext-scraper');
const { mergePrices, formatOverview } = require('./mergePrices');
const store = require('./store');

const OUTPUT_DIR = process.env.OUTPUT_DIR || './output';
const PLAYERS_FILE = './players.json';
const DELAY_MS = parseInt(process.env.DELAY_MS || '1000', 10);
const MAX_AGE_MINUTES = parseInt(process.env.MAX_AGE_MINUTES || '30', 10);
const TIMING_LOG = path.join(OUTPUT_DIR, 'scrape-timings.log');

if (!fs.existsSync(OUTPUT_DIR)) fs.mkdirSync(OUTPUT_DIR, { recursive: true });

const SCRAPERS = { futbin: futbinScraper, futgg: futggScraper, futwiz: futwizScraper, futnext: futnextScraper };

function loadPlayersConfig() {
  if (!fs.existsSync(PLAYERS_FILE)) {
    console.log(`❌ ${PLAYERS_FILE} not found.`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(PLAYERS_FILE, 'utf8')).players;
}

function findPlayerDef(playerId) {
  return loadPlayersConfig().find(p => String(p.playerId) === String(playerId));
}

function logTiming(playerId, playerName, timing, success) {
  const entry = { timestamp: new Date().toISOString(), playerId, playerName, timing, success };
  try {
    fs.appendFileSync(TIMING_LOG, JSON.stringify(entry) + '\n');
  } catch (e) {
    console.error('⚠️  Could not write timing log:', e.message);
  }
}

async function scrapeSource(source, playerName, url) {
  try {
    return await SCRAPERS[source].scrape(playerName, url);
  } catch (e) {
    console.error(`❌ ${source} failed:`, e.message);
    return null;
  }
}

async function timedScrapeSource(source, playerName, url, timing) {
  const start = Date.now();
  const result = await scrapeSource(source, playerName, url);
  const ms = Date.now() - start;
  timing[source] = ms;
  console.log(`    ⏱  ${source}: ${ms}ms`);
  return result;
}

async function scrapePlayerFull(playerDef) {
  const { playerName, playerId, urls } = playerDef;
  console.log(`\n🔍 Scraping all sources for: ${playerName}`);

  const overallStart = Date.now();
  const timing = {};

  const [futbinData, futggData, futwizData, futnextData] = await Promise.all([
    timedScrapeSource('futbin', playerName, urls.futbin, timing),
    timedScrapeSource('futgg', playerName, urls.futgg, timing),
    timedScrapeSource('futwiz', playerName, urls.futwiz, timing),
    timedScrapeSource('futnext', playerName, urls.futnext, timing),
  ]);

  timing.total = Date.now() - overallStart;
  console.log(`    ⏱  total: ${timing.total}ms`);

  const merged = mergePrices({ playerName, futbinData, futggData, futwizData, futnextData });
  merged.timing = timing;

  logTiming(playerId, playerName, timing, {
    futbin: !!futbinData, futgg: !!futggData, futwiz: !!futwizData, futnext: !!futnextData,
  });

  return merged;
}

async function cmdScrapeAll() {
  const players = loadPlayersConfig();
  const results = [];

  for (const playerDef of players) {
    const merged = await scrapePlayerFull(playerDef);
    console.log('\n' + formatOverview(merged));
    if (merged) {
      results.push(merged);
      if (playerDef.playerId) store.upsertEntry(playerDef.playerId, merged);
    }
    await new Promise(r => setTimeout(r, DELAY_MS));
  }

  const outputPath = path.join(OUTPUT_DIR, 'cards.json');
  fs.writeFileSync(outputPath, JSON.stringify({ players: results }, null, 2));
  console.log(`\n📁 Saved to: ${outputPath}`);
  console.log(`📁 DB updated: ${store.DB_FILE}`);
  console.log(`📁 Timing log: ${TIMING_LOG}`);
}

async function cmdGet(playerId, { json }) {
  const entry = store.getEntry(playerId);

  if (entry && !store.isStale(entry, MAX_AGE_MINUTES)) {
    if (json) console.log(JSON.stringify(entry, null, 2));
    else console.log('\n' + formatOverview(entry) + `\n\n(from cache, stored ${entry.storedAt})`);
    return;
  }

  console.log(entry ? `⏰ Cache older than ${MAX_AGE_MINUTES}min - refreshing...` : `ℹ️  Not cached yet - fetching...`);
  await cmdRefresh(playerId, { json });
}

async function cmdRefresh(playerId, { source, json } = {}) {
  const playerDef = findPlayerDef(playerId);
  if (!playerDef) {
    console.log(`❌ playerId ${playerId} not found in players.json`);
    process.exit(1);
  }

  let merged;

  if (!source) {
    merged = await scrapePlayerFull(playerDef);
  } else {
    if (!SCRAPERS[source]) {
      console.log(`❌ Unknown source "${source}". Use one of: futbin, futgg, futwiz, futnext`);
      process.exit(1);
    }
    const existing = store.getEntry(playerId) || { sources: {} };
    const start = Date.now();
    const freshData = await scrapeSource(source, playerDef.playerName, playerDef.urls[source]);
    console.log(`    ⏱  ${source}: ${Date.now() - start}ms`);

    const updatedSources = {
      ...existing.sources,
      [source]: freshData || existing.sources?.[source] || { error: 'Failed to scrape' },
    };
    const asDataOrNull = (s) => (updatedSources[s]?.error ? null : updatedSources[s]);
    merged = mergePrices({
      playerName: playerDef.playerName,
      futbinData: asDataOrNull('futbin'),
      futggData: asDataOrNull('futgg'),
      futwizData: asDataOrNull('futwiz'),
      futnextData: asDataOrNull('futnext'),
    });
  }

  store.upsertEntry(playerId, merged);
  if (json) console.log(JSON.stringify(merged, null, 2));
  else console.log('\n' + formatOverview(merged));
}

function parseArgs(argv) {
  const [cmd, ...rest] = argv;
  const flags = {};
  const positional = [];
  for (const arg of rest) {
    if (arg.startsWith('--')) {
      const [key, val] = arg.slice(2).split('=');
      flags[key] = val === undefined ? true : val;
    } else {
      positional.push(arg);
    }
  }
  return { cmd, positional, flags };
}

(async () => {
  const { cmd, positional, flags } = parseArgs(process.argv.slice(2));

  if (!cmd || cmd === 'scrape-all') {
    await cmdScrapeAll();
  } else if (cmd === 'get') {
    if (!positional[0]) { console.log('Usage: node index.js get <playerId> [--json]'); process.exit(1); }
    await cmdGet(positional[0], { json: !!flags.json });
  } else if (cmd === 'refresh') {
    if (!positional[0]) {
      console.log('Usage: node index.js refresh <playerId> [--source=futbin] [--json]');
      process.exit(1);
    }
    await cmdRefresh(positional[0], { source: flags.source, json: !!flags.json });
  } else {
    console.log('Usage:');
    console.log('  node index.js                                scrape all players.json entries');
    console.log('  node index.js get <playerId> [--json]         overview from cache, auto-refresh if stale');
    console.log('  node index.js refresh <playerId> [--json]     force full refresh (all 4 sources)');
    console.log('  node index.js refresh <playerId> --source=futbin   refresh only 1 source');
  }

  process.exit(0);
})();

'@
Set-Content -Path ".\index.js" -Value $content_index_js -NoNewline
Write-Host "  wrote index.js" -ForegroundColor Green

$content_mergePrices_js = @'
/**
 * MERGE DATA from all 4 sources into one composite card object.
 *
 * NEW in v4:
 * - cardVersion: fallback chain across all 4 sources (FUT.GG's "Rarity"
 *   field is the most structurally reliable, tried first) + a mismatch
 *   flag if sources disagree (e.g. one says "Gold Rare", another "TOTW" -
 *   would mean you're comparing two different cards by mistake).
 * - binPricePercentInRange: where the current FUTBIN price sits within
 *   its own historical price range (0% = at the range low, 100% = at the
 *   range high). Only computed from FUTBIN's range since that's the only
 *   source that reliably provides one.
 * - recentSales: FUTBIN's mini sales list, passed through.
 * - formatOverview(): human-readable summary block for CLI display.
 */

function firstNonNull(...vals) {
  for (const v of vals) if (v !== null && v !== undefined) return v;
  return null;
}

function formatMomentum(m) {
  if (!m) return null;
  return `avg ${m.average} (range ${m.lowest}-${m.highest})`;
}

function calculateAverage(prices) {
  const valid = prices.filter(p => typeof p === 'number' && !isNaN(p));
  if (valid.length === 0) return null;
  return Math.round(valid.reduce((a, b) => a + b, 0) / valid.length);
}

function checkVersionAgreement(futbinV, futggV, futwizV, futnextV) {
  const versions = [futbinV, futggV, futwizV, futnextV].filter(Boolean).map(v => v.toLowerCase().trim());
  if (versions.length < 2) return { checked: false, agree: null };
  const unique = [...new Set(versions)];
  return { checked: true, agree: unique.length === 1, values: { futbin: futbinV, futgg: futggV, futwiz: futwizV, futnext: futnextV } };
}

function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData }) {
  const binPrices = {
    futbin: futbinData?.lowestPrice ?? null,
    futgg: futggData?.lowestBin ?? null,
    futwiz: futwizData?.marketValue ?? null,
    futnext: futnextData?.currentCheapest ?? null,
  };

  const validBins = Object.entries(binPrices).filter(([, v]) => typeof v === 'number');
  let lowestAcrossSources = null;
  if (validBins.length) {
    const [source, price] = validBins.reduce((min, cur) => (cur[1] < min[1] ? cur : min));
    lowestAcrossSources = { source, price };
  }

  let binPricePercentInRange = null;
  if (futbinData?.priceRange && typeof binPrices.futbin === 'number') {
    const { min, max } = futbinData.priceRange;
    if (typeof min === 'number' && typeof max === 'number' && max > min) {
      binPricePercentInRange = Math.round(((binPrices.futbin - min) / (max - min)) * 1000) / 10; // 1 decimal
    }
  }

  const cardVersion = firstNonNull(futggData?.cardVersion, futwizData?.cardVersion, futbinData?.cardVersion, futnextData?.cardVersion);
  const versionCheck = checkVersionAgreement(futbinData?.cardVersion, futggData?.cardVersion, futwizData?.cardVersion, futnextData?.cardVersion);

  return {
    playerName,
    playerId: firstNonNull(futggData?.playerId, futnextData?.futnextId, futwizData?.playerId, futwizData?.cardId),
    cardVersion,
    versionCheck,
    sources: {
      futbin: futbinData || { error: 'Failed to scrape' },
      futgg: futggData || { error: 'Failed to scrape' },
      futwiz: futwizData || { error: 'Failed to scrape' },
      futnext: futnextData || { error: 'Failed to scrape' },
    },
    merged: {
      binPrices,
      lowestAcrossSources,
      averageBinPrice: calculateAverage(Object.values(binPrices)),
      binPricePercentInRange,
      priceRange: futbinData?.priceRange ?? null,
      futbinLowest5: futbinData?.lowestPrices ?? null,
      futbinLowest5Count: futbinData?.lowestPricesCount ?? null,
      recentSales: futbinData?.recentSales ?? null,
      liveAuctionsFutgg: futggData?.liveAuctionsRaw ?? null,
      recentSalesFutgg: futggData?.recentSalesRaw ?? null,
      rating: firstNonNull(futggData?.rating),
      position: firstNonNull(futggData?.position),
      club: firstNonNull(futggData?.club),
      nation: firstNonNull(futggData?.nation),
      trend: firstNonNull(futbinData?.trend, futggData?.priceMomentum ? formatMomentum(futggData.priceMomentum) : null),
      lastUpdated: new Date().toISOString(),
    },
  };
}

function formatOverview(merged) {
  const m = merged.merged || {};
  const lines = [];
  lines.push(`━━━ ${merged.playerName}${merged.cardVersion ? ' — ' + merged.cardVersion : ''} ━━━`);
  if (merged.versionCheck?.checked && !merged.versionCheck.agree) {
    lines.push(`⚠️  Card version MISMATCH across sources: ${JSON.stringify(merged.versionCheck.values)}`);
  }
  lines.push(`Rating: ${m.rating ?? '?'}  Position: ${m.position ?? '?'}  Club: ${m.club ?? '?'}  Nation: ${m.nation ?? '?'}`);
  lines.push('');
  lines.push('BIN prices:');
  lines.push(`  FUTBIN:  ${m.binPrices?.futbin ?? '—'}`);
  lines.push(`  FUT.GG:  ${m.binPrices?.futgg ?? '—'}`);
  lines.push(`  FUTWIZ:  ${m.binPrices?.futwiz ?? '—'}`);
  lines.push(`  FutNext: ${m.binPrices?.futnext ?? '—'}`);
  lines.push(`  Average: ${m.averageBinPrice ?? '—'}`);
  if (m.lowestAcrossSources) lines.push(`  Cheapest right now: ${m.lowestAcrossSources.price} on ${m.lowestAcrossSources.source}`);
  if (m.priceRange) {
    lines.push(`  Price range (FUTBIN): ${m.priceRange.min} - ${m.priceRange.max}${m.binPricePercentInRange !== null ? ` (currently at ${m.binPricePercentInRange}% of range)` : ''}`);
  }
  if (m.trend) lines.push(`  Trend: ${m.trend}`);
  if (m.futbinLowest5?.length) lines.push(`  FUTBIN top-5 lowest: ${m.futbinLowest5.join(', ')}`);
  if (m.recentSales?.length) {
    lines.push('');
    lines.push('Recent sales (FUTBIN):');
    m.recentSales.slice(0, 5).forEach(s => lines.push(`  ${s.when ?? s.raw ?? '?'}${s.amount ? ' — ' + s.amount : ''}`));
  }
  lines.push('');
  if (merged.timing) {
    const t = merged.timing;
    lines.push(`Scraped in ${t.total}ms (futbin ${t.futbin ?? '-'}ms, futgg ${t.futgg ?? '-'}ms, futwiz ${t.futwiz ?? '-'}ms, futnext ${t.futnext ?? '-'}ms)`);
  }
  lines.push(`Last updated: ${m.lastUpdated}`);
  return lines.join('\n');
}

module.exports = { mergePrices, formatOverview };

'@
Set-Content -Path ".\mergePrices.js" -Value $content_mergePrices_js -NoNewline
Write-Host "  wrote mergePrices.js" -ForegroundColor Green

$content_README_md = @'
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


'@
Set-Content -Path ".\README.md" -Value $content_README_md -NoNewline
Write-Host "  wrote README.md" -ForegroundColor Green

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host "  Test: node index.js get 231747" -ForegroundColor Yellow
Write-Host "  Then check: Get-Content .\output\scrape-timings.log" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "feat: timing log, lowestPricesCount, updated README"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}