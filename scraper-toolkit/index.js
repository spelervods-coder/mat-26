/**
 * FC26 SCRAPER ORCHESTRATOR (v10)
 *
 * NEW (v10): human-in-the-loop transaction logging + pricing engine.
 * You perform the actual buy/list/sell actions in-game; this system
 * logs them via ONE short command each and immediately hands back the
 * next recommended number. All engine output is a RECOMMENDATION only -
 * nothing here touches your EA account.
 *
 * Usage:
 *   node index.js                              scrape ALL players.json entries
 *   node index.js get <cardId>                  pretty overview (from cache, auto-refresh if stale)
 *   node index.js refresh <cardId>               force full refresh (all 4 sources)
 *   node index.js buy <cardId> <price>            log a purchase, get recommended sell price
 *   node index.js list <positionId> <price>       log that you listed it
 *   node index.js sold <positionId> <price>        log a sale, closes the position, shows profit
 *   node index.js expired <positionId>             log an unsold expiry, get a fresh relist price
 *   node index.js relist <positionId> <price>      log that you relisted it
 *   node index.js positions                        dashboard: all open positions + slot count
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');

const futbinScraper = require('./futbin-scraper');
const futggScraper = require('./futgg-scraper');
const futwizScraper = require('./futwiz-scraper');
const futnextScraper = require('./futnext-scraper');
const pricingEngine = require('./pricing-engine');
const positionsStore = require('./positions-store');
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

// Strips a leading UTF-8 BOM if present. PowerShell's `Set-Content
// -Encoding UTF8` (Windows PowerShell 5.1) always writes a BOM, which
// breaks JSON.parse with "Unexpected token" - add-player.ps1 and
// manage-players.ps1 are fixed to not write one, but this is a defensive
// second layer in case players.json got a BOM some other way.
function stripBOM(text) {
  return text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
}

function loadPlayersConfig() {
  if (!fs.existsSync(PLAYERS_FILE)) {
    console.log(`❌ ${PLAYERS_FILE} not found.`);
    process.exit(1);
  }
  const raw = stripBOM(fs.readFileSync(PLAYERS_FILE, 'utf8'));
  return JSON.parse(raw).players;
}

function savePlayersConfig(players) {
  // Explicitly UTF-8 without BOM - fs.writeFileSync never adds one, but
  // stated here so this stays true if the write method ever changes.
  fs.writeFileSync(PLAYERS_FILE, JSON.stringify({ players }, null, 2), 'utf8');
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
//
// withSales=false skips the extra FUTBIN sales-history page load
// (--prices-only mode) - faster, but no salesPerHourEstimate/
// bidBinBreakdown for that run.
async function scrapePlayerFull(playerDef, { withSales = true } = {}) {
  const { playerName, urls } = playerDef;
  console.log(`\n🔍 Scraping all sources for: ${playerName}${withSales ? '' : ' (prices only)'}`);

  const overallStart = Date.now();
  const timing = {};

  // FUTBIN sales-history runs as its own Puppeteer session (separate
  // page: /sales/ vs /market) but in PARALLEL with the other 4, not
  // after - same pattern as timedScrapeSource, just a different scraper
  // function. Gives real bid/bin/expired classified transaction data.
  async function timedScrapeSalesHistory() {
    if (!withSales) return null;
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

// Shown after every overview so TOS is visible during normal screening
// (get/refresh/scrape-all), not just at buy-time.
function printTOS(merged) {
  if (!merged?.merged) return;
  const tos = pricingEngine.calculateTOS(merged.merged);
  const flag = tos.tos >= 7.0 ? '  ✅ boven drempel (7.0)' : '';
  console.log(`\n🎯 TOS score: ${tos.tos}/10${flag}`);
  console.log(`   profit ${tos.subScores.profit} · liquidity ${tos.subScores.liquidity} · mean-rev ${tos.subScores.meanReversion} · range ${tos.subScores.range}`);
}

async function cmdScrapeAll({ withSales = true } = {}) {
  const players = loadPlayersConfig();
  const results = [];

  for (const playerDef of players) {
    const merged = await scrapePlayerFull(playerDef, { withSales });
    console.log('\n' + formatOverview(merged));
    printTOS(merged);
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
    else {
      console.log('\n' + formatOverview(entry) + `\n\n(from cache, stored ${entry.storedAt})`);
      printTOS(entry);
    }
    return;
  }

  console.log(entry ? `⏰ Cache older than ${MAX_AGE_MINUTES}min - refreshing...` : `ℹ️  Not cached yet - fetching...`);
  await cmdRefresh(id, { json });
}

async function cmdRefresh(id, { source, json, withSales = true } = {}) {
  const playerDef = findPlayerDef(id);
  if (!playerDef) {
    console.log(`❌ cardId ${id} not found in players.json`);
    process.exit(1);
  }

  let merged;

  if (!source) {
    merged = await scrapePlayerFull(playerDef, { withSales });
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
  else {
    console.log('\n' + formatOverview(merged));
    printTOS(merged);
  }
}

const MAX_RELISTS = 3;
const ACCOUNT_BUDGET = parseInt(process.env.ACCOUNT_BUDGET || '0', 10);
const RISK_PROFILE = process.env.RISK_PROFILE || 'standard';

function shortId(positionId) {
  return positionId.slice(0, 8);
}

function resolvePositionId(idOrPrefix) {
  const full = positionsStore.getPosition(idOrPrefix);
  if (full) return full;
  return positionsStore.findPositionByPrefix(idOrPrefix);
}

// Accepts EITHER a specific positionId (explicit control) OR a cardId
// (auto-resolves via FIFO to the oldest position currently in one of the
// allowed states for this action - cards of the same cardId are
// fungible, EA doesn't track which literal instance you act on).
function resolvePositionForAction(idOrCardId, allowedLastActions) {
  const explicit = resolvePositionId(idOrCardId);
  if (explicit) return explicit;
  return positionsStore.findOldestOpenPositionForCard(idOrCardId, allowedLastActions);
}

// node index.js buy <cardId> <price>
// Logs a purchase, immediately shows the recommended sell price using
// whatever price data is currently cached (run `refresh` first if stale).
async function cmdBuy(cardId, priceStr) {
  const price = parseInt(priceStr, 10);
  if (!price) { console.log('Usage: node index.js buy <cardId> <price>'); process.exit(1); }

  const playerDef = findPlayerDef(cardId);
  if (!playerDef) { console.log(`❌ cardId ${cardId} not found in players.json`); process.exit(1); }

  const position = positionsStore.createPosition(cardId, playerDef.playerName, price);
  console.log(`\n✅ BUY gelogd: ${playerDef.playerName} voor ${price}`);
  console.log(`   Position ID: ${position.positionId}  (kort: ${shortId(position.positionId)})`);

  const cached = store.getEntry(cardId);
  const activeSlots = positionsStore.countActiveSlots();
  const inventoryQ = positionsStore.countPositionsForCard(cardId);

  if (cached?.merged) {
    const rec = pricingEngine.recommendPrices(cached.merged, {
      riskProfile: RISK_PROFILE, activeSlots, inventoryQ,
    });
    if (rec) {
      const tos = pricingEngine.calculateTOS(cached.merged);
      console.log(`\n💡 Aanbevolen verkoopprijs: ${rec.sellPrice}`);
      console.log(`   Verwachte winst: ${rec.expectedProfit}  |  ROI: ${rec.expectedRoiPct}%  |  TOS: ${tos.tos}/10`);
      console.log(`   Actieve slots: ${activeSlots}/100  |  Van dit kaarttype: ${inventoryQ}`);
    }
  } else {
    console.log(`⚠️  Geen prijsdata in cache - run eerst: node index.js refresh ${cardId}`);
  }

  console.log(`\nVolgende stap: node index.js list ${shortId(position.positionId)} <prijs>`);
}

// node index.js list <positionId|cardId> <price>
async function cmdList(idOrCardId, priceStr) {
  const price = parseInt(priceStr, 10);
  const pos = resolvePositionForAction(idOrCardId, ['buy']);
  if (!pos) { console.log(`❌ Geen open (net-gekochte) positie gevonden voor "${idOrCardId}"`); process.exit(1); }

  positionsStore.addEvent(pos.positionId, { action: 'list', price, listDurationMin: 60 });
  console.log(`✅ LIST gelogd: ${pos.playerName} voor ${price} (60 min)  [${shortId(pos.positionId)}]`);
  console.log(`Volgende stap: node index.js sold ${pos.cardId} <prijs>  of  node index.js expired ${pos.cardId}`);
}

// node index.js sold <positionId|cardId> <price>
async function cmdSold(idOrCardId, priceStr) {
  const price = parseInt(priceStr, 10);
  const pos = resolvePositionForAction(idOrCardId, ['list', 'relist']);
  if (!pos) { console.log(`❌ Geen open (gelistte) positie gevonden voor "${idOrCardId}"`); process.exit(1); }

  const netPrice = Math.round(price * (1 - pricingEngine.EA_TAX));
  const updated = positionsStore.addEvent(pos.positionId, { action: 'sold', price, netPrice });
  console.log(`✅ SOLD gelogd: ${updated.playerName} voor ${price} (netto ${netPrice})  [${shortId(pos.positionId)}]`);
  console.log(`💰 Winst: ${updated.finalProfit >= 0 ? '+' : ''}${updated.finalProfit}`);
}

// node index.js expired <positionId|cardId>
// Logs the expiry, checks relist count vs max, then re-scrapes fresh
// data and recommends a NEW relist price (not a fixed decrement).
async function cmdExpired(idOrCardId) {
  const pos = resolvePositionForAction(idOrCardId, ['list', 'relist']);
  if (!pos) { console.log(`❌ Geen open (gelistte) positie gevonden voor "${idOrCardId}"`); process.exit(1); }

  const updated = positionsStore.addEvent(pos.positionId, { action: 'expire' });
  console.log(`⏰ EXPIRE gelogd: ${updated.playerName}  [${shortId(pos.positionId)}]`);
  console.log(`   Let op: EA plaatst dit NIET automatisch terug in je club - blijft een slot bezetten tot je 'm ophaalt.`);

  if (updated.relistCount >= MAX_RELISTS) {
    positionsStore.addEvent(pos.positionId, { action: 'stuck' });
    console.log(`🔴 Max relists (${MAX_RELISTS}) bereikt - gemarkeerd als STUCK. Handmatige review nodig.`);
    return;
  }

  const playerDef = findPlayerDef(updated.cardId);
  if (!playerDef) {
    console.log(`⚠️  cardId ${updated.cardId} niet meer in players.json - kan geen verse relist-prijs berekenen.`);
    return;
  }

  console.log('   Verse data ophalen voor relist-advies...');
  const fresh = await scrapePlayerFull(playerDef, { withSales: true });
  storeAndLog(playerDef, fresh);

  const lastListEvent = [...updated.events].reverse().find(e => e.action === 'list' || e.action === 'relist');
  const activeSlots = positionsStore.countActiveSlots();
  const inventoryQ = positionsStore.countPositionsForCard(updated.cardId);
  const rec = pricingEngine.recommendRelistPrice(fresh.merged, lastListEvent.price, {
    riskProfile: RISK_PROFILE, activeSlots, inventoryQ,
  });

  if (rec) {
    console.log(`\n💡 Nieuwe relist-prijs: ${rec.sellPrice} (was ${lastListEvent.price}${rec.wasCapped ? ', afgetopt op max 15% stap' : ''})`);
    console.log(`Volgende stap: node index.js relist ${updated.cardId} ${rec.sellPrice}`);
  }
}

// node index.js relist <positionId|cardId> <price>
async function cmdRelist(idOrCardId, priceStr) {
  const price = parseInt(priceStr, 10);
  const pos = resolvePositionForAction(idOrCardId, ['expire']);
  if (!pos) { console.log(`❌ Geen open (verlopen) positie gevonden voor "${idOrCardId}"`); process.exit(1); }

  const updated = positionsStore.addEvent(pos.positionId, { action: 'relist', price, listDurationMin: 60 });
  console.log(`✅ RELIST #${updated.relistCount} gelogd: ${updated.playerName} voor ${price}  [${shortId(pos.positionId)}]`);
  console.log(`Volgende stap: node index.js sold ${updated.cardId} <prijs>  of  node index.js expired ${updated.cardId}`);
}

// node index.js positions - dashboard
async function cmdPositionsDashboard() {
  const open = positionsStore.getOpenPositions();
  const activeSlots = positionsStore.countActiveSlots();
  const pressure = pricingEngine.slotPressureMultiplier(activeSlots);

  console.log(`\n━━━ Positie-dashboard ━━━`);
  console.log(`Actieve transferlijst-slots: ${activeSlots}/100  (marge-druk-factor: ${Math.round(pressure * 100)}%)`);

  if (!open.length) {
    console.log('\nGeen open posities.');
  } else {
    console.log('');
    open.forEach(p => {
      const lastEvent = p.events[p.events.length - 1];
      console.log(`  [${shortId(p.positionId)}] ${p.playerName} — laatste actie: ${lastEvent.action}${lastEvent.price ? ` (${lastEvent.price})` : ''} — relists: ${p.relistCount}`);
    });
  }

  const all = positionsStore.getAllPositions();
  const closed = all.filter(p => p.status === 'closed');
  const stuck = all.filter(p => p.status === 'stuck');
  if (closed.length) {
    const totalProfit = closed.reduce((sum, p) => sum + (p.finalProfit || 0), 0);
    console.log(`\nAfgesloten posities: ${closed.length}  |  Totale winst: ${totalProfit >= 0 ? '+' : ''}${totalProfit}`);
  }
  if (stuck.length) {
    console.log(`⚠️  Stuck posities: ${stuck.length} — review nodig`);
  }
}

// node index.js scores
// Screening tool: ranks every player in players.json by cached TOS score
// so you can quickly see who to keep/swap while building a watchlist.
// Uses whatever is in players-db.json - run `node index.js` first to
// refresh everything, or `refresh <cardId>` per candidate.
async function cmdListScores() {
  const players = loadPlayersConfig();
  const rows = players.map(p => {
    const id = getEntryId(p);
    const cached = id ? store.getEntry(id) : null;
    const tos = cached?.merged ? pricingEngine.calculateTOS(cached.merged) : null;
    return {
      playerName: p.playerName,
      cardId: id,
      tos: tos?.tos ?? null,
      cardVersion: cached?.cardVersion ?? null,
    };
  });

  rows.sort((a, b) => (b.tos ?? -1) - (a.tos ?? -1));

  console.log('\n━━━ Score-overzicht (players.json, laatste cache) ━━━\n');
  rows.forEach(r => {
    const scoreStr = r.tos !== null ? r.tos.toFixed(1) : ' — ';
    const flag = r.tos !== null && r.tos >= 7.0 ? '✅' : '  ';
    console.log(`${flag} ${String(scoreStr).padStart(5)}  ${r.playerName}${r.cardVersion ? ' (' + r.cardVersion + ')' : ''}  [${r.cardId ?? '?'}]`);
  });

  const above = rows.filter(r => r.tos !== null && r.tos >= 7.0).length;
  const missing = rows.filter(r => r.tos === null).length;
  console.log(`\n${above}/${rows.length} spelers >= TOS 7.0${missing ? `  (${missing} nog geen data — run eerst: node index.js)` : ''}`);
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
  const withSales = !flags['prices-only'];

  if (!cmd || cmd === 'scrape-all') {
    await cmdScrapeAll({ withSales });
  } else if (cmd === 'get') {
    if (!positional[0]) { console.log('Usage: node index.js get <cardId> [--json]'); process.exit(1); }
    await cmdGet(positional[0], { json: !!flags.json });
  } else if (cmd === 'refresh') {
    if (!positional[0]) {
      console.log('Usage: node index.js refresh <cardId> [--source=futbin] [--prices-only] [--json]');
      process.exit(1);
    }
    await cmdRefresh(positional[0], { source: flags.source, json: !!flags.json, withSales });
  } else if (cmd === 'buy') {
    if (!positional[0] || !positional[1]) { console.log('Usage: node index.js buy <cardId> <price>'); process.exit(1); }
    await cmdBuy(positional[0], positional[1]);
  } else if (cmd === 'list') {
    if (!positional[0] || !positional[1]) { console.log('Usage: node index.js list <positionId> <price>'); process.exit(1); }
    await cmdList(positional[0], positional[1]);
  } else if (cmd === 'sold') {
    if (!positional[0] || !positional[1]) { console.log('Usage: node index.js sold <positionId> <price>'); process.exit(1); }
    await cmdSold(positional[0], positional[1]);
  } else if (cmd === 'expired') {
    if (!positional[0]) { console.log('Usage: node index.js expired <positionId>'); process.exit(1); }
    await cmdExpired(positional[0]);
  } else if (cmd === 'relist') {
    if (!positional[0] || !positional[1]) { console.log('Usage: node index.js relist <positionId> <price>'); process.exit(1); }
    await cmdRelist(positional[0], positional[1]);
  } else if (cmd === 'positions') {
    await cmdPositionsDashboard();
  } else if (cmd === 'scores') {
    await cmdListScores();
  } else {
    console.log('Usage:');
    console.log('  node index.js [--prices-only]                 scrape all players.json entries');
    console.log('                                                 (--prices-only skips FUTBIN sales history, faster)');
    console.log('  node index.js get <cardId> [--json]           overview from cache, auto-refresh if stale');
    console.log('  node index.js refresh <cardId> [--json]       force full refresh (all 4 sources + sales history)');
    console.log('  node index.js refresh <cardId> --prices-only   force refresh, skip sales history (faster)');
    console.log('  node index.js refresh <cardId> --source=futbin   refresh only 1 source, keep rest cached');
    console.log('  node index.js scores                           ranglijst: alle players.json op TOS-score');
    console.log('');
    console.log('  --- transactie-logging (human-in-the-loop) ---');
    console.log('  <positionId> mag ook <cardId> zijn - dan wordt automatisch de oudste');
    console.log('  passende positie gekozen (FIFO, kaarten van hetzelfde type zijn fungibel)');
    console.log('  node index.js buy <cardId> <price>             log aankoop, krijg aanbevolen verkoopprijs');
    console.log('  node index.js list <cardId|positionId> <price>        log dat je gelist hebt');
    console.log('  node index.js sold <cardId|positionId> <price>        log verkoop, sluit positie, toont winst');
    console.log('  node index.js expired <cardId|positionId>              log niet-verkocht, krijg verse relist-prijs');
    console.log('  node index.js relist <cardId|positionId> <price>      log relist');
    console.log('  node index.js positions                        dashboard: alle open posities + slot-telling');
  }

  process.exit(0);
})();
