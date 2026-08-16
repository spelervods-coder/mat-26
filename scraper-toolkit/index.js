/**
 * FC26 SCRAPER ORCHESTRATOR (v3 - CLI commands + persistent store)
 *
 * Usage:
 *   node index.js                              scrape ALL players in players.json,
 *                                               write output/cards.json + upsert DB
 *   node index.js get <playerId>                read from DB; auto-refreshes if
 *                                               missing or older than MAX_AGE_MINUTES
 *   node index.js refresh <playerId>            force full refresh (all 4 sources)
 *   node index.js refresh <playerId> --source=futbin
 *                                               force refresh ONLY that one source,
 *                                               other sources kept from cache
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');

const futbinScraper = require('./futbin-scraper');
const futggScraper = require('./futgg-scraper');
const futwizScraper = require('./futwiz-scraper');
const futnextScraper = require('./futnext-scraper');
const { mergePrices } = require('./mergePrices');
const store = require('./store');

const OUTPUT_DIR = process.env.OUTPUT_DIR || './output';
const PLAYERS_FILE = './players.json';
const DELAY_MS = parseInt(process.env.DELAY_MS || '1000', 10);
const MAX_AGE_MINUTES = parseInt(process.env.MAX_AGE_MINUTES || '30', 10);

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

async function scrapeSource(source, playerName, url) {
  try {
    return await SCRAPERS[source].scrape(playerName, url);
  } catch (e) {
    console.error(`❌ ${source} failed:`, e.message);
    return null;
  }
}

async function scrapePlayerFull(playerDef) {
  const { playerName, urls } = playerDef;
  console.log(`\n🔍 Scraping all sources for: ${playerName}`);

  const [futbinData, futggData, futwizData, futnextData] = await Promise.all([
    scrapeSource('futbin', playerName, urls.futbin),
    scrapeSource('futgg', playerName, urls.futgg),
    scrapeSource('futwiz', playerName, urls.futwiz),
    scrapeSource('futnext', playerName, urls.futnext),
  ]);

  const merged = mergePrices({ playerName, futbinData, futggData, futwizData, futnextData });
  console.log(`✅ Merged data:`, JSON.stringify(merged, null, 2));
  return merged;
}

async function cmdScrapeAll() {
  const players = loadPlayersConfig();
  const results = [];

  for (const playerDef of players) {
    const merged = await scrapePlayerFull(playerDef);
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
}

async function cmdGet(playerId) {
  const entry = store.getEntry(playerId);

  if (entry && !store.isStale(entry, MAX_AGE_MINUTES)) {
    console.log(`✅ From cache (stored ${entry.storedAt}, max age ${MAX_AGE_MINUTES}min):`);
    console.log(JSON.stringify(entry, null, 2));
    return;
  }

  console.log(
    entry
      ? `⏰ Cache is older than ${MAX_AGE_MINUTES}min - refreshing...`
      : `ℹ️  Not cached yet - fetching...`
  );
  await cmdRefresh(playerId, {});
}

async function cmdRefresh(playerId, { source } = {}) {
  const playerDef = findPlayerDef(playerId);
  if (!playerDef) {
    console.log(`❌ playerId ${playerId} not found in players.json`);
    process.exit(1);
  }

  if (!source) {
    const merged = await scrapePlayerFull(playerDef);
    store.upsertEntry(playerId, merged);
    return;
  }

  if (!SCRAPERS[source]) {
    console.log(`❌ Unknown source "${source}". Use one of: futbin, futgg, futwiz, futnext`);
    process.exit(1);
  }

  const existing = store.getEntry(playerId) || { sources: {} };
  const freshData = await scrapeSource(source, playerDef.playerName, playerDef.urls[source]);

  const updatedSources = {
    ...existing.sources,
    [source]: freshData || existing.sources?.[source] || { error: 'Failed to scrape' },
  };

  const asDataOrNull = (s) => (updatedSources[s]?.error ? null : updatedSources[s]);

  const merged = mergePrices({
    playerName: playerDef.playerName,
    futbinData: asDataOrNull('futbin'),
    futggData: asDataOrNull('futgg'),
    futwizData: asDataOrNull('futwiz'),
    futnextData: asDataOrNull('futnext'),
  });

  store.upsertEntry(playerId, merged);
  console.log(`✅ Refreshed [${source}] for ${playerDef.playerName}:`);
  console.log(JSON.stringify(merged, null, 2));
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
    if (!positional[0]) { console.log('Usage: node index.js get <playerId>'); process.exit(1); }
    await cmdGet(positional[0]);
  } else if (cmd === 'refresh') {
    if (!positional[0]) {
      console.log('Usage: node index.js refresh <playerId> [--source=futbin]');
      process.exit(1);
    }
    await cmdRefresh(positional[0], { source: flags.source });
  } else {
    console.log('Usage:');
    console.log('  node index.js                                scrape all players.json entries');
    console.log('  node index.js get <playerId>                 get from cache, auto-refresh if stale');
    console.log('  node index.js refresh <playerId>              force full refresh (all 4 sources)');
    console.log('  node index.js refresh <playerId> --source=futbin   refresh only 1 source');
  }

  process.exit(0);
})();
