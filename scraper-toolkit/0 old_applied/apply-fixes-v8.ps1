# apply-fixes-v8.ps1
# - FIX (important): was keying the DB/logs on 'playerId', which is NOT
#   unique per card (a player's Gold Rare, TOTW, Icon etc share the same
#   playerId but have DIFFERENT cardIds). Now uses cardId as canonical key,
#   backward-compatible with existing players.json entries.
# - NEW: cardId auto-backfill - if you add a player without a cardId,
#   the first scrape fills it in automatically.
# - NEW: validate.js - Stage 1 code-quality/syntax check, now wired into
#   git-checkpoint.ps1 so it runs automatically before every commit and
#   BLOCKS the commit if it fails.
# - NEW: scheduler.ps1 - run in a separate terminal to keep
#   price-history.jsonl filling in the background while you keep testing.
# - CHANGED: add-player.ps1 / manage-players.ps1 now ask for 'Card ID'
#   instead of 'Player ID', and player name is now optional (auto-guessed
#   from the FUTBIN URL slug if left blank).
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v8 files..." -ForegroundColor Cyan

$content_index_js = @'
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
    // CARD-specific ID (itemId/cardId) - NOT the same across a player's
    // different card versions (base Gold Rare vs TOTW vs Icon etc all
    // have DIFFERENT cardIds but the SAME playerId). This is the
    // canonical unique key for tracking one specific card.
    cardId: firstNonNull(futggData?.itemId, futwizData?.cardId, futggData?.playerId, futwizData?.playerId),
    // The PERSON's ID - stays constant across all of a player's cards.
    // Kept separately so you could later query "all cards for this player".
    playerId: firstNonNull(futggData?.playerId, futwizData?.playerId),
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

$content_add_player_ps1 = @'
# add-player.ps1
# Interactive helper: paste the 4 URLs (+ optional name + cardId) for ONE
# player, appends a correctly-formatted entry to players.json.
#
# cardId = the CARD-specific ID (FUT.GG's itemId, or FUTWIZ's Card ID) -
# NOT the same across a player's different versions (Gold Rare vs TOTW vs
# Icon all have DIFFERENT cardIds, even for the same person). This is what
# uniquely identifies the exact card you want to track.

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

Write-Host "--- Add a new player ---" -ForegroundColor Cyan
$futbinUrl  = Read-Host "FUTBIN URL"
$futggUrl   = Read-Host "FUT.GG URL"
$futwizUrl  = Read-Host "FUTWIZ URL"
$futnextUrl = Read-Host "FutNext URL"
$cardId     = Read-Host "Card ID (from fut.gg itemId / futwiz Card ID - blank = auto-fill on first scrape)"
$playerName = Read-Host "Player name (blank = guessed from FUTBIN URL)"

if (-not $playerName) {
  # crude auto-derive from URL slug: .../player/40/kylian-mbappe/... -> "Kylian Mbappe"
  if ($futbinUrl -match '/player/\d+/([a-z0-9\-]+)') {
    $slug = $Matches[1]
    $playerName = ($slug -split '-' | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ' '
    Write-Host "  (guessed name: $playerName)" -ForegroundColor Yellow
  } else {
    $playerName = "Unknown"
  }
}

$json = Get-Content ".\players.json" -Raw | ConvertFrom-Json

$newPlayer = [PSCustomObject]@{
  playerName = $playerName
  cardId     = $cardId
  urls       = [PSCustomObject]@{
    futbin  = $futbinUrl
    futgg   = $futggUrl
    futwiz  = $futwizUrl
    futnext = $futnextUrl
  }
}

if ($cardId) {
  $existingIds = $json.players | ForEach-Object { $_.cardId }
  if ($existingIds -contains $cardId) {
    Write-Host "WARNING: cardId $cardId already exists in players.json." -ForegroundColor Yellow
  }
}

$json.players = @($json.players) + $newPlayer
$json | ConvertTo-Json -Depth 10 | Set-Content ".\players.json" -Encoding UTF8

Write-Host "`nAdded $playerName. Total players: $($json.players.Count)" -ForegroundColor Green
if (-not $cardId) {
  Write-Host "No cardId given - it will be filled in automatically the first time this player is scraped (via 'node index.js')." -ForegroundColor Yellow
}
Write-Host "Run .\add-player.ps1 again for the next player." -ForegroundColor Yellow

'@
Set-Content -Path ".\add-player.ps1" -Value $content_add_player_ps1 -NoNewline
Write-Host "  wrote add-player.ps1" -ForegroundColor Green

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
    Write-Host "[$i] $($p.playerName) (id=$($p.cardId))"
    $i++
  }
  Write-Host ""
}

function Add-PlayerInteractive($json) {
  Write-Host "--- Add player ---" -ForegroundColor Cyan
  $playerName = Read-Host "Player name"
  $cardId   = Read-Host "Card ID (fut.gg itemId / futwiz Card ID)"
  $futbinUrl  = Read-Host "FUTBIN URL"
  $futggUrl   = Read-Host "FUT.GG URL"
  $futwizUrl  = Read-Host "FUTWIZ URL"
  $futnextUrl = Read-Host "FutNext URL"

  $newPlayer = [PSCustomObject]@{
    playerName = $playerName
    playerId   = $cardId
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
  $v = Read-Host "Player ID [$($p.cardId)]";           if ($v) { $p.cardId = $v }
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

$content_validate_js = @'
#!/usr/bin/env node
/**
 * Stage 1 code-quality check: syntax validation for every .js file in this
 * folder (via `node --check`, syntax-only, doesn't execute anything), plus
 * confirms every *-scraper.js exports a scrape() function.
 *
 * Run standalone: node validate.js
 * Exit code 0 = pass, 1 = fail. Called automatically by git-checkpoint.ps1
 * before every commit - a failing check blocks the commit.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const dir = __dirname;
const jsFiles = fs.readdirSync(dir).filter(f => f.endsWith('.js') && f !== 'validate.js');

let ok = true;

console.log('🔍 Stage 1: Code quality check\n');

for (const file of jsFiles) {
  const filePath = path.join(dir, file);
  try {
    execSync(`node --check "${filePath}"`, { stdio: 'pipe' });
    console.log(`  ✅ ${file}: syntax OK`);
  } catch (e) {
    console.log(`  ❌ ${file}: SYNTAX ERROR`);
    console.log('    ' + (e.stderr?.toString() || e.message).split('\n').join('\n    '));
    ok = false;
  }
}

const scraperFiles = jsFiles.filter(f => f.endsWith('-scraper.js'));
for (const file of scraperFiles) {
  try {
    delete require.cache[require.resolve(path.join(dir, file))];
    const mod = require(path.join(dir, file));
    if (typeof mod.scrape !== 'function') {
      console.log(`  ❌ ${file}: does not export a scrape() function`);
      ok = false;
    } else {
      console.log(`  ✅ ${file}: exports scrape()`);
    }
  } catch (e) {
    console.log(`  ❌ ${file}: failed to load - ${e.message}`);
    ok = false;
  }
}

if (ok) {
  console.log('\n✅ Stage 1 PASSED\n');
  process.exit(0);
} else {
  console.log('\n❌ Stage 1 FAILED - fix issues above before committing\n');
  process.exit(1);
}

'@
Set-Content -Path ".\validate.js" -Value $content_validate_js -NoNewline
Write-Host "  wrote validate.js" -ForegroundColor Green

$content_scheduler_ps1 = @'
# scheduler.ps1
# Runs a full scrape-all every N minutes, indefinitely, filling
# output/price-history.jsonl over time. Leave this running in its OWN
# terminal window while you keep testing/developing in another one.
#
# Usage:
#   .\scheduler.ps1                  (default: every 30 min)
#   .\scheduler.ps1 -IntervalMinutes 15
#
# Stop with Ctrl+C.

param(
  [int]$IntervalMinutes = 30
)

Write-Host "Scheduler started: full scrape-all every $IntervalMinutes minutes." -ForegroundColor Cyan
Write-Host "Leave this window open. Ctrl+C to stop." -ForegroundColor Cyan

while ($true) {
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "`n[$now] Running scrape-all..." -ForegroundColor Yellow
  node index.js
  $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$now] Done. Sleeping $IntervalMinutes minutes..." -ForegroundColor Yellow
  Start-Sleep -Seconds ($IntervalMinutes * 60)
}

'@
Set-Content -Path ".\scheduler.ps1" -Value $content_scheduler_ps1 -NoNewline
Write-Host "  wrote scheduler.ps1" -ForegroundColor Green

$content_git_checkpoint = @'
param(
  [Parameter(Mandatory=$true)]
  [string]$Message
)

$repoPath = (Get-Location).Path
git config --global --add safe.directory $repoPath | Out-Null

# Stage 1 code-quality gate: run validate.js on scraper-toolkit before
# allowing any commit. Skipped gracefully if the file doesn't exist yet.
if (Test-Path "scraper-toolkit\validate.js") {
  Write-Host "`nRunning code quality check (scraper-toolkit)..." -ForegroundColor Cyan
  Push-Location scraper-toolkit
  node validate.js
  $validateExitCode = $LASTEXITCODE
  Pop-Location
  if ($validateExitCode -ne 0) {
    Write-Host "`nCode quality check FAILED - commit aborted. Fix the issues above and try again." -ForegroundColor Red
    exit 1
  }
}

git add -A
$staged = git diff --cached --stat

if ([string]::IsNullOrWhiteSpace($staged)) {
  Write-Host "Nothing to commit - working tree matches last commit." -ForegroundColor Yellow
  exit 0
}

Write-Host "`nStaged changes:" -ForegroundColor Cyan
Write-Host $staged

git commit -m $Message

if ($LASTEXITCODE -eq 0) {
  Write-Host "`nCommitted: $Message" -ForegroundColor Green
  git push origin main
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Pushed to GitHub." -ForegroundColor Green
  } else {
    Write-Host "Push failed - if this is your first push, try:" -ForegroundColor Red
    Write-Host "  git push -u origin main" -ForegroundColor Yellow
    Write-Host "If remote has unrelated commits (README etc), try:" -ForegroundColor Red
    Write-Host "  git pull origin main --allow-unrelated-histories" -ForegroundColor Yellow
  }
} else {
  Write-Host "Commit failed - check errors above." -ForegroundColor Red
}

'@
Set-Content -Path "..\scripts\git-checkpoint.ps1" -Value $content_git_checkpoint -NoNewline
Write-Host "  updated ..\scripts\git-checkpoint.ps1 (now runs validate.js before commits)" -ForegroundColor Green

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host "  Test: node validate.js" -ForegroundColor Yellow
Write-Host "  Test: node index.js refresh 231747" -ForegroundColor Yellow
Write-Host "  Background collection: .\scheduler.ps1  (run in a SEPARATE terminal)" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "fix: cardId as canonical key (was playerId); add validate.js code-quality gate + scheduler.ps1"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}