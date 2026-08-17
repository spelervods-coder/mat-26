# apply-fixes-v7.ps1
# - BUG FIX: futbin recentSales was letting a giant comment-thread blob
#   through (class-name collision with the reviews widget). Now filtered.
# - NEW: output/price-history.jsonl - separate append-only time-series log
#   of price snapshots (distinct from players-db.json which only holds the
#   latest). Foundation for a future KPI/scoring engine.
# - NEW: dataFreshness field (FUTBIN's 'X ago' freshness indicator) shown
#   in the overview alongside 'cheapest right now'.
# - NEW: manage-players.ps1 - list/add/edit/remove players via a menu
#   (add-player.ps1 still works for quick single adds).
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v7 files..." -ForegroundColor Cyan

$content_futbin_scraper_js = @'
/**
 * FUTBIN SCRAPER (v6)
 *
 * FIXED cardVersion: was guessing at a breadcrumb format that doesn't
 * actually exist. Confirmed via direct fetch that FUTBIN's page always
 * contains a stable sentence: "<Name>'s <Version> card is rated <rating>"
 * - even in non-hydrated HTML. Using that instead.
 *
 * FIXED recentSales: the "find element with exact text 'Latest Sales'
 * then walk up" logic wasn't reliably finding the right container.
 * Reverted to the simpler, already-proven-working direct class query.
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
      const lowestPricesCount = lowestPrices.length;

      const bodyText = document.body.innerText;

      const rangeMatch = bodyText.match(/PRICE RANGE:\s*\n?\s*([\d,]+)\s*-\s*([\d,]+)/i);
      const priceRange = rangeMatch ? { min: num(rangeMatch[1]), max: num(rangeMatch[2]) } : null;
      const updatedMatch = bodyText.match(/PRICE UPDATED:\s*([^\n]+)/i);
      const priceUpdated = updatedMatch ? clean(updatedMatch[1]) : null;

      const avgBinMatch = bodyText.match(/Average BIN\s*\n?\s*([\d,]+)/i);
      const cheapestMatch = bodyText.match(/Cheapest Sale\s*\n?\s*(?:[A-Za-z]{3}\s*\d+,?\s*[\d:APM\s]*\n?\s*)?([\d,]+)/i);
      const eaAvgMatch = bodyText.match(/EA Avg\.?\s*Price\s*\n?\s*([\d,]+)/i);

      const trendMatch = bodyText.match(/Trend:\s*([\-\d.]+%\s*\([^)]+\))/i);

      // FIXED: reliable "<Name>'s <Version> card is rated" sentence, confirmed via live fetch
      const versionMatch = bodyText.match(/['\u2019]s\s+(.+?)\s+card is rated/i);
      const cardVersion = versionMatch ? versionMatch[1].trim() : null;

      // FIXED (v7): the .xs-column.full-width class is ALSO used somewhere
      // in the comments/reviews widget on this page - the old {raw: text}
      // fallback was letting a giant comment-thread blob through as a
      // "sale". Now: only keep rows matching the exact date+amount shape,
      // AND add a length guard as a second safety net. No fallback.
      const salesRows = Array.from(document.querySelectorAll('.xs-column.full-width'))
        .map(el => clean(el.textContent))
        .filter(Boolean)
        .filter(text => text.length < 100); // real sale rows are short; comment blobs are not
      const recentSales = salesRows
        .map(text => {
          const m = text.match(/^(.+?\d{1,2}:\d{2}\s*[AP]M)\s*([\d,.]+K?)/i);
          return m ? { when: m[1].trim(), amount: m[2].trim() } : null;
        })
        .filter(Boolean); // drop anything that doesn't match the expected shape - no raw fallback

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
const PRICE_HISTORY_LOG = path.join(OUTPUT_DIR, 'price-history.jsonl');

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

// Separate from players-db.json (which only holds the LATEST snapshot).
// This appends every scrape as its own line, building a time-series -
// needed later for sales-per-hour / volatility analysis (KPI engine).
// Deliberately lean (no raw per-source dumps) to keep file size sane.
function logPriceSnapshot(playerId, playerName, merged) {
  const m = merged.merged || {};
  const entry = {
    timestamp: new Date().toISOString(),
    playerId,
    playerName,
    cardVersion: merged.cardVersion,
    binPrices: m.binPrices,
    averageBinPrice: m.averageBinPrice,
    lowestAcrossSources: m.lowestAcrossSources,
    priceRange: m.priceRange,
    binPricePercentInRange: m.binPricePercentInRange,
    trend: m.trend,
  };
  try {
    fs.appendFileSync(PRICE_HISTORY_LOG, JSON.stringify(entry) + '\n');
  } catch (e) {
    console.error('⚠️  Could not write price history log:', e.message);
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
  if (playerId) logPriceSnapshot(playerId, playerName, merged);

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
    dataFreshness: { futbin: futbinData?.priceUpdated ?? null }, // only FUTBIN exposes this natively so far
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
  if (merged.dataFreshness?.futbin) lines.push(`  FUTBIN data freshness: ${merged.dataFreshness.futbin}`);
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

$content_manage_players_ps1 = @'
# manage-players.ps1
# Interactive menu: list, add, edit, or remove players in players.json.
# (add-player.ps1 still works too, for a quick single add without the menu.)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

function Load-Players {
  return Get-Content ".\players.json" -Raw | ConvertFrom-Json
}

function Save-Players($json) {
  $json | ConvertTo-Json -Depth 10 | Set-Content ".\players.json" -Encoding UTF8
}

function List-Players($json) {
  Write-Host ""
  $i = 0
  foreach ($p in $json.players) {
    Write-Host "[$i] $($p.playerName) (id=$($p.playerId))"
    $i++
  }
  Write-Host ""
}

function Add-PlayerInteractive($json) {
  Write-Host "--- Add player ---" -ForegroundColor Cyan
  $playerName = Read-Host "Player name"
  $playerId   = Read-Host "Player ID (from fut.gg or futnext URL)"
  $futbinUrl  = Read-Host "FUTBIN URL"
  $futggUrl   = Read-Host "FUT.GG URL"
  $futwizUrl  = Read-Host "FUTWIZ URL"
  $futnextUrl = Read-Host "FutNext URL"

  $newPlayer = [PSCustomObject]@{
    playerName = $playerName
    playerId   = $playerId
    urls       = [PSCustomObject]@{
      futbin  = $futbinUrl
      futgg   = $futggUrl
      futwiz  = $futwizUrl
      futnext = $futnextUrl
    }
  }
  $json.players = @($json.players) + $newPlayer
  Save-Players $json
  Write-Host "Added $playerName." -ForegroundColor Green
  return $json
}

function Edit-PlayerInteractive($json) {
  List-Players $json
  $idxInput = Read-Host "Which number to edit? (blank to cancel)"
  if (-not $idxInput) { return $json }
  $idx = [int]$idxInput
  if ($idx -lt 0 -or $idx -ge $json.players.Count) { Write-Host "Invalid index." -ForegroundColor Red; return $json }

  $p = $json.players[$idx]
  Write-Host "Editing $($p.playerName) - press Enter to keep the current value" -ForegroundColor Cyan

  $v = Read-Host "Player name [$($p.playerName)]";      if ($v) { $p.playerName = $v }
  $v = Read-Host "Player ID [$($p.playerId)]";           if ($v) { $p.playerId = $v }
  $v = Read-Host "FUTBIN URL [$($p.urls.futbin)]";       if ($v) { $p.urls.futbin = $v }
  $v = Read-Host "FUT.GG URL [$($p.urls.futgg)]";        if ($v) { $p.urls.futgg = $v }
  $v = Read-Host "FUTWIZ URL [$($p.urls.futwiz)]";       if ($v) { $p.urls.futwiz = $v }
  $v = Read-Host "FutNext URL [$($p.urls.futnext)]";     if ($v) { $p.urls.futnext = $v }

  Save-Players $json
  Write-Host "Updated $($p.playerName)." -ForegroundColor Green
  return $json
}

function Remove-PlayerInteractive($json) {
  List-Players $json
  $idxInput = Read-Host "Which number to remove? (blank to cancel)"
  if (-not $idxInput) { return $json }
  $idx = [int]$idxInput
  if ($idx -lt 0 -or $idx -ge $json.players.Count) { Write-Host "Invalid index." -ForegroundColor Red; return $json }

  $removed = $json.players[$idx]
  $confirm = Read-Host "Remove $($removed.playerName)? (y/n)"
  if ($confirm -eq "y") {
    $json.players = @($json.players | Where-Object { $_.playerId -ne $removed.playerId })
    Save-Players $json
    Write-Host "Removed $($removed.playerName)." -ForegroundColor Green
  }
  return $json
}

$json = Load-Players
$loop = $true
while ($loop) {
  Write-Host ""
  Write-Host "--- Player Manager ($($json.players.Count) players) ---" -ForegroundColor Cyan
  Write-Host "1) List players"
  Write-Host "2) Add player"
  Write-Host "3) Edit player"
  Write-Host "4) Remove player"
  Write-Host "5) Exit"
  $choice = Read-Host "Choice"
  switch ($choice) {
    "1" { List-Players $json }
    "2" { $json = Add-PlayerInteractive $json }
    "3" { $json = Edit-PlayerInteractive $json }
    "4" { $json = Remove-PlayerInteractive $json }
    "5" { $loop = $false }
    default { Write-Host "Invalid choice." -ForegroundColor Red }
  }
}

'@
Set-Content -Path ".\manage-players.ps1" -Value $content_manage_players_ps1 -NoNewline
Write-Host "  wrote manage-players.ps1" -ForegroundColor Green

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host "  Test: node index.js refresh 231747" -ForegroundColor Yellow
Write-Host "  Manage players: .\manage-players.ps1" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "fix: recentSales comment-blob bug; add price-history log + manage-players.ps1"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}