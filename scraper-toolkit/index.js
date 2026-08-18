/**
 * FC26 SCRAPER ORCHESTRATOR (v8)
 *
 * NEW: cardId auto-backfill. If a player was added without a cardId
 * (add-player.ps1 allows this), the first scrape derives it from FUT.GG's
 * itemId / FUTWIZ's cardId (via mergePrices.js) and writes it back into
 * players.json so subsequent runs have a stable key.
 *
 * FIXED: was keying everything on "playerId", which is NOT unique per
 * card (a player's Gold Rare, TOTW, Icon etc all share the same playerId
 * but have DIFFERENT cardIds). Now uses cardId as the canonical key, with
 * backward-compatible fallback to the old "playerId" field for entries
 * added before this fix.
 *
 * Usage:
 *   node index.js                              scrape ALL players.json entries
 *   node index.js get <cardId>                  pretty overview (from cache, auto-refresh if stale)
 *   node index.js get <cardId> --json            same, but raw JSON instead of the overview
 *   node index.js refresh <cardId>               force full refresh (all 4 sources)
 *   node index.js refresh <cardId> --source=futbin   refresh only 1 source
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

function savePlayersConfig(players) {
  fs.writeFileSync(PLAYERS_FILE, JSON.stringify({ players }, null, 2));
}

// Backward compatible: old entries used "playerId" as the (mistaken)
// unique key; new entries use "cardId" (the correct one - see
// mergePrices.js). This resolves either, preferring cardId.
function getEntryId(playerDef) {
  return playerDef.cardId ?? playerDef.playerId ?? null;
}

function findPlayerDef(id) {
  return loadPlayersConfig().find(p => String(getEntryId(p)) === String(id));
}

// If a player was added without a cardId, fill it in now (matched by
// futbin URL, which is required and unique) so future runs have a stable key.
function backfillCardIdIfMissing(playerDef, derivedCardId) {
  if (getEntryId(playerDef) || !derivedCardId) return;
  const players = loadPlayersConfig();
  const match = players.find(p => p.urls?.futbin === playerDef.urls?.futbin);
  if (match && !getEntryId(match)) {
    match.cardId = derivedCardId;
    savePlayersConfig(players);
    console.log(`  📝 Backfilled cardId ${derivedCardId} for ${playerDef.playerName} into players.json`);
  }
}

function logTiming(id, playerName, timing, success) {
  const entry = { timestamp: new Date().toISOString(), cardId: id, playerName, timing, success };
  try {
    fs.appendFileSync(TIMING_LOG, JSON.stringify(entry) + '\n');
  } catch (e) {
    console.error('⚠️  Could not write timing log:', e.message);
  }
}

// Separate from players-db.json (which only holds the LATEST snapshot).
// This appends every scrape as its own line, building a time-series -
// needed later for sales-per-hour / volatility analysis (KPI engine).
function logPriceSnapshot(id, playerName, merged) {
  const m = merged.merged || {};
  const entry = {
    timestamp: new Date().toISOString(),
    cardId: id,
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
  timing[source] = Date.now() - start;
  console.log(`    ⏱  ${source}: ${timing[source]}ms`);
  return result;
}

// Pure scrape+merge - no store/log side effects (those happen in the
// callers below, AFTER cardId backfill is resolved).
async function scrapePlayerFull(playerDef) {
  const { playerName, urls } = playerDef;
  console.log(`\n🔍 Scraping all sources for: ${playerName}`);

  const overallStart = Date.now();
  const timing = {};

  // FUTBIN sales-history runs as its own Puppeteer session (separate
  // page: /sales/ vs /market) but in PARALLEL with the other 4, not
  // after - same pattern as timedScrapeSource, just a different scraper
  // function. Gives real bid/bin/expired classified transaction data.
  async function timedScrapeSalesHistory() {
    const start = Date.now();
    let result = null;
    try {
      result = await futbinScraper.scrapeSalesHistory(playerName, urls.futbin);
    } catch (e) {
      console.error('❌ FUTBIN sales history failed:', e.message);
    }
    timing.futbinSales = Date.now() - start;
    console.log(`    ⏱  futbinSales: ${timing.futbinSales}ms`);
    return result;
  }

  const [futbinData, futggData, futwizData, futnextData, futbinSalesData] = await Promise.all([
    timedScrapeSource('futbin', playerName, urls.futbin, timing),
    timedScrapeSource('futgg', playerName, urls.futgg, timing),
    timedScrapeSource('futwiz', playerName, urls.futwiz, timing),
    timedScrapeSource('futnext', playerName, urls.futnext, timing),
    timedScrapeSalesHistory(),
  ]);

  timing.total = Date.now() - overallStart;
  console.log(`    ⏱  total: ${timing.total}ms`);

  const merged = mergePrices({ playerName, futbinData, futggData, futwizData, futnextData, futbinSalesData });
  merged.timing = timing;
  return merged;
}

function storeAndLog(playerDef, merged) {
  let id = getEntryId(playerDef);
  if (!id && merged.cardId) {
    backfillCardIdIfMissing(playerDef, merged.cardId);
    id = merged.cardId;
  }
  if (!id) {
    console.log('  ⚠️  No cardId available (not found on any source) - skipping DB/log write for this player.');
    return;
  }
  store.upsertEntry(id, merged);
  logTiming(id, playerDef.playerName, merged.timing, {
    futbin: !merged.sources.futbin?.error, futgg: !merged.sources.futgg?.error,
    futwiz: !merged.sources.futwiz?.error, futnext: !merged.sources.futnext?.error,
  });
  logPriceSnapshot(id, playerDef.playerName, merged);
}

async function cmdScrapeAll() {
  const players = loadPlayersConfig();
  const results = [];

  for (const playerDef of players) {
    const merged = await scrapePlayerFull(playerDef);
    console.log('\n' + formatOverview(merged));
    if (merged) {
      results.push(merged);
      storeAndLog(playerDef, merged);
    }
    await new Promise(r => setTimeout(r, DELAY_MS));
  }

  const outputPath = path.join(OUTPUT_DIR, 'cards.json');
  fs.writeFileSync(outputPath, JSON.stringify({ players: results }, null, 2));
  console.log(`\n📁 Saved to: ${outputPath}`);
  console.log(`📁 DB updated: ${store.DB_FILE}`);
  console.log(`📁 Timing log: ${TIMING_LOG}`);
  console.log(`📁 Price history: ${PRICE_HISTORY_LOG}`);
}

async function cmdGet(id, { json }) {
  const entry = store.getEntry(id);

  if (entry && !store.isStale(entry, MAX_AGE_MINUTES)) {
    if (json) console.log(JSON.stringify(entry, null, 2));
    else console.log('\n' + formatOverview(entry) + `\n\n(from cache, stored ${entry.storedAt})`);
    return;
  }

  console.log(entry ? `⏰ Cache older than ${MAX_AGE_MINUTES}min - refreshing...` : `ℹ️  Not cached yet - fetching...`);
  await cmdRefresh(id, { json });
}

async function cmdRefresh(id, { source, json } = {}) {
  const playerDef = findPlayerDef(id);
  if (!playerDef) {
    console.log(`❌ cardId ${id} not found in players.json`);
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
    const existing = store.getEntry(id) || { sources: {} };
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
    merged.timing = null;
  }

  storeAndLog(playerDef, merged);
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
    if (!positional[0]) { console.log('Usage: node index.js get <cardId> [--json]'); process.exit(1); }
    await cmdGet(positional[0], { json: !!flags.json });
  } else if (cmd === 'refresh') {
    if (!positional[0]) {
      console.log('Usage: node index.js refresh <cardId> [--source=futbin] [--json]');
      process.exit(1);
    }
    await cmdRefresh(positional[0], { source: flags.source, json: !!flags.json });
  } else {
    console.log('Usage:');
    console.log('  node index.js                                scrape all players.json entries');
    console.log('  node index.js get <cardId> [--json]           overview from cache, auto-refresh if stale');
    console.log('  node index.js refresh <cardId> [--json]       force full refresh (all 4 sources)');
    console.log('  node index.js refresh <cardId> --source=futbin   refresh only 1 source');
  }

  process.exit(0);
})();
