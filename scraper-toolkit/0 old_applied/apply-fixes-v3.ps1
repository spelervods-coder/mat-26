# apply-fixes-v3.ps1
# Adds: FUTBIN top-5 prices, composite merge logic, persistent JSON store,
# get/refresh CLI commands, add-player.ps1 helper.
# Auto-commits + pushes to git at the end.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v3 files..." -ForegroundColor Cyan

$content_futbin_scraper_js = @'
/**
 * FUTBIN SCRAPER (v3 - top 5 lowest prices)
 *
 * Returns up to 5 lowest listed prices (not just the single lowest),
 * taken from the main price display + the "lowest prices" side list.
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

      // Grab up to 5 lowest prices: use leaf elements only (no children) to
      // avoid double-counting parent+child text, then prepend the main
      // price if it's not already the first entry.
      function extractPrices(container) {
        if (!container) return [];
        const leafEls = Array.from(container.querySelectorAll('*')).filter(el => el.children.length === 0);
        const candidates = leafEls.length ? leafEls : Array.from(container.children);
        return candidates.map(el => num(el.textContent)).filter(n => n !== null);
      }

      let lowestPrices = extractPrices(document.querySelector('.lowest-prices-wrapper'));
      if (lowestPrice !== null && lowestPrices[0] !== lowestPrice) {
        lowestPrices.unshift(lowestPrice);
      }
      lowestPrices = lowestPrices.slice(0, 5);

      const priceBoxText = clean(document.querySelector('.price-box-full-width-xxs-column')?.textContent) || '';
      const rangeMatch = priceBoxText.match(/([\d,]+)\s*-\s*([\d,]+)/);
      const priceRange = rangeMatch ? { min: num(rangeMatch[1]), max: num(rangeMatch[2]) } : null;
      const updatedMatch = priceBoxText.match(/Price Updated:\s*(.+?)(?:Price Range|$)/i);
      const priceUpdated = updatedMatch ? clean(updatedMatch[1]) : null;

      const marketGridText = clean(document.querySelector('.market-grid.platform-pc-only')?.textContent) || '';
      const avgBinMatch = marketGridText.match(/Average BIN\s*([\d,]+)/i);
      const cheapestMatch = marketGridText.match(/Cheapest Sale[^\d]*([\d,]+)/i);
      const eaAvgMatch = marketGridText.match(/EA Avg\. Price\s*([\d,]+)/i);

      const bodyText = document.body.innerText;
      const trendMatch = bodyText.match(/Trend:\s*([\-\d.]+%\s*\([^)]+\))/i);

      return {
        lowestPrice,
        lowestPrices,
        priceRange,
        priceUpdated,
        averageBin: avgBinMatch ? num(avgBinMatch[1]) : null,
        cheapestSale: cheapestMatch ? num(cheapestMatch[1]) : null,
        eaAveragePrice: eaAvgMatch ? num(eaAvgMatch[1]) : null,
        trend: trendMatch ? trendMatch[1].trim() : null,
      };
    });

    const result = {
      source: 'FUTBIN',
      ...data,
      url,
      timestamp: new Date().toISOString(),
    };

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

$content_futgg_scraper_js = @'
/**
 * FUT.GG SCRAPER (v2 - URL-based)
 *
 * FIX: "Lowest BIN" price is picked by finding the exact text node
 * "Lowest BIN" first, then taking the NEXT tabular-nums span after it in
 * DOM order - NOT just the first tabular-nums on the page. There are
 * other tabular-nums elements earlier in the page (percentage badges
 * near the player card) that were being picked up incorrectly before.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, url) {
  console.log(`  📊 FUT.GG: Scraping "${playerName}"...`);

  let browser;
  try {
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

    await page.waitForFunction(
      () => document.body.innerText.includes('Lowest BIN'),
      { timeout: 15000 }
    );

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };

      // Find the leaf element whose exact text is "Lowest BIN", then find
      // the first span.tabular-nums that comes AFTER it in document order.
      function findValueAfterLabel(labelText) {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
        let foundLabel = false;
        let node;
        while ((node = walker.nextNode())) {
          if (!foundLabel) {
            if (node.children.length === 0 && node.textContent.trim() === labelText) {
              foundLabel = true;
            }
            continue;
          }
          if (node.matches && node.matches('span.tabular-nums')) {
            return node.textContent;
          }
        }
        return null;
      }

      const lowestBin = num(findValueAfterLabel('Lowest BIN'));

      const bodyText = document.body.innerText;

      const playerIdMatch = bodyText.match(/Player ID\s*(\d+)/i);
      const itemIdMatch = bodyText.match(/Item ID\s*(\d+)/i);
      const ratingMatch = bodyText.match(/\n(\d{2,3})\n\s*\n?\s*(ST|CF|LW|RW|CAM|CM|CDM|LM|RM|LB|RB|CB|LWB|RWB|GK)\b/);
      const clubMatch = bodyText.match(/Club\s*\n?\s*([A-Za-zÀ-ÿ0-9 .'-]+?)(?:\n|League)/);
      const nationMatch = bodyText.match(/Nation\s*\n?\s*([A-Za-zÀ-ÿ .'-]+?)(?:\n|Rarity)/);
      const momentumMatch = bodyText.match(/Lowest\s*\n?\s*([\d,]+)\s*\n?\s*Average\s*\n?\s*([\d,]+)\s*\n?\s*Highest\s*\n?\s*([\d,]+)/i);

      return {
        lowestBin,
        rating: ratingMatch ? num(ratingMatch[1]) : null,
        position: ratingMatch ? ratingMatch[2] : null,
        club: clubMatch ? clubMatch[1].trim() : null,
        nation: nationMatch ? nationMatch[1].trim() : null,
        playerId: playerIdMatch ? playerIdMatch[1] : null,
        itemId: itemIdMatch ? itemIdMatch[1] : null,
        priceMomentum: momentumMatch
          ? { lowest: num(momentumMatch[1]), average: num(momentumMatch[2]), highest: num(momentumMatch[3]) }
          : null,
      };
    });

    const result = {
      source: 'FUT.GG',
      name: playerName,
      ...data,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FUT.GG:`, result);
    return result;

  } catch (error) {
    console.error(`    ❌ FUT.GG Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };

'@
Set-Content -Path ".\futgg-scraper.js" -Value $content_futgg_scraper_js -NoNewline
Write-Host "  wrote futgg-scraper.js" -ForegroundColor Green

$content_futwiz_scraper_js = @'
/**
 * FUTWIZ SCRAPER (v2 - URL-based)
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, url) {
  console.log(`  📊 FUTWIZ: Scraping "${playerName}"...`);

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: process.env.HEADLESS !== 'false',
      executablePath: process.env.CHROME_PATH || undefined,
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
    });

    const page = await browser.newPage();
    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    );

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 20000 });
    await page.waitForSelector('[class*="text-cyan-300"]', { timeout: 15000 });

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };

      const priceEl = document.querySelector('[class*="text-cyan-300"]');
      const marketValue = num(priceEl?.textContent);

      const bodyText = document.body.innerText;
      const cardIdMatch = bodyText.match(/Card ID\s*\n?\s*([A-Za-z0-9]+)/i);
      const playerIdMatch = bodyText.match(/Player ID\s*\n?\s*([A-Za-z0-9]+)/i);
      const addedMatch = bodyText.match(/Added\s*\n?\s*([A-Za-z]+ \d{1,2},?\s*\d{4}[^\n]*)/i);
      const likesMatch = bodyText.match(/(\d+)%?\s*Like/i);

      return {
        marketValue,
        cardId: cardIdMatch ? cardIdMatch[1] : null,
        playerId: playerIdMatch ? playerIdMatch[1] : null,
        added: addedMatch ? addedMatch[1].trim().split('\n')[0] : null,
        likesPercent: likesMatch ? parseInt(likesMatch[1], 10) : null,
      };
    });

    const result = {
      source: 'FUTWIZ',
      ...data,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FUTWIZ:`, result);
    return result;

  } catch (error) {
    console.error(`    ❌ FUTWIZ Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };

'@
Set-Content -Path ".\futwiz-scraper.js" -Value $content_futwiz_scraper_js -NoNewline
Write-Host "  wrote futwiz-scraper.js" -ForegroundColor Green

$content_futnext_scraper_js = @'
/**
 * FUTNEXT SCRAPER (v2 - URL-based)
 *
 * URL is used AS-IS (no re-encoding) - if pasted straight from the
 * browser address bar it is already percent-encoded correctly.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, url) {
  console.log(`  📊 FutNext: Scraping "${playerName}"...`);

  let browser;
  try {
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
    await page.waitForFunction(
      () => document.body.innerText.includes('Lowest'),
      { timeout: 15000 }
    );

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };

      const bodyText = document.body.innerText;

      const cheapestMatch = bodyText.match(/^([\d,]+)\s*$/m);
      const lowest24hMatch = bodyText.match(/Lowest\s*\(24H\)\s*\n?\s*([\d,]+)/i);
      const avg24hMatch = bodyText.match(/Average\s*\(24H\)\s*\n?\s*([\d,]+)/i);
      const changeMatch = bodyText.match(/([\-\+]?[\d,]+)\s*\(([\-\d.]+)%\)/);

      return {
        currentCheapest: cheapestMatch ? num(cheapestMatch[1]) : lowest24hMatch ? num(lowest24hMatch[1]) : null,
        lowest24h: lowest24hMatch ? num(lowest24hMatch[1]) : null,
        average24h: avg24hMatch ? num(avg24hMatch[1]) : null,
        change24h: changeMatch ? { amount: num(changeMatch[1]), percent: parseFloat(changeMatch[2]) } : null,
      };
    });

    const result = {
      source: 'FutNext',
      ...data,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FutNext:`, result);
    return result;

  } catch (error) {
    console.error(`    ❌ FutNext Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };

'@
Set-Content -Path ".\futnext-scraper.js" -Value $content_futnext_scraper_js -NoNewline
Write-Host "  wrote futnext-scraper.js" -ForegroundColor Green

$content_index_js = @'
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

'@
Set-Content -Path ".\index.js" -Value $content_index_js -NoNewline
Write-Host "  wrote index.js" -ForegroundColor Green

$content_mergePrices_js = @'
/**
 * MERGE DATA from all 4 sources into one composite card object.
 *
 * Approach (simple, will be refined later per user's note):
 * - Per-field FALLBACK CHAIN: for fields only some sources provide
 *   (rating, club, trend, playerId), take the first non-null value from
 *   a priority-ordered list of sources.
 * - BIN prices: keep ALL 4 raw values (binPrices), plus:
 *   - averageBinPrice: mean of whatever sources responded
 *   - lowestAcrossSources: {source, price} of the single cheapest BIN
 *     found anywhere - useful for "where to buy cheapest right now"
 * - No cross-source validation/discrepancy-flagging yet (e.g. warning
 *   when two sources disagree wildly) - noted as a future improvement.
 */

function firstNonNull(...vals) {
  for (const v of vals) {
    if (v !== null && v !== undefined) return v;
  }
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

  return {
    playerName,
    playerId: firstNonNull(futggData?.playerId, futnextData?.futnextId, futwizData?.playerId, futwizData?.cardId),
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
      futbinLowest5: futbinData?.lowestPrices ?? null,
      rating: firstNonNull(futggData?.rating),
      position: firstNonNull(futggData?.position),
      club: firstNonNull(futggData?.club),
      nation: firstNonNull(futggData?.nation),
      trend: firstNonNull(
        futbinData?.trend,
        futggData?.priceMomentum ? formatMomentum(futggData.priceMomentum) : null
      ),
      lastUpdated: new Date().toISOString(),
    },
  };
}

module.exports = { mergePrices };

'@
Set-Content -Path ".\mergePrices.js" -Value $content_mergePrices_js -NoNewline
Write-Host "  wrote mergePrices.js" -ForegroundColor Green

$content_store_js = @'
/**
 * SIMPLE JSON-BACKED STORE for scraped player data.
 *
 * File: output/players-db.json - keyed by playerId (EA official ID).
 * Phase 1 storage (per project roadmap): JSON now, SQLite later once
 * this outgrows a flat file (e.g. >200 players or concurrent writes).
 */

const fs = require('fs');
const path = require('path');

const DB_FILE = path.join(process.env.OUTPUT_DIR || './output', 'players-db.json');

function loadDb() {
  if (!fs.existsSync(DB_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
  } catch (e) {
    console.error('⚠️  Could not parse players-db.json, starting fresh:', e.message);
    return {};
  }
}

function saveDb(db) {
  const dir = path.dirname(DB_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
}

function getEntry(playerId) {
  const db = loadDb();
  return db[playerId] || null;
}

function upsertEntry(playerId, mergedData) {
  const db = loadDb();
  db[playerId] = {
    ...mergedData,
    storedAt: new Date().toISOString(),
  };
  saveDb(db);
  return db[playerId];
}

function isStale(entry, maxAgeMinutes) {
  if (!entry || !entry.storedAt) return true;
  const ageMs = Date.now() - new Date(entry.storedAt).getTime();
  return ageMs > maxAgeMinutes * 60 * 1000;
}

module.exports = { loadDb, saveDb, getEntry, upsertEntry, isStale, DB_FILE };

'@
Set-Content -Path ".\store.js" -Value $content_store_js -NoNewline
Write-Host "  wrote store.js" -ForegroundColor Green

if (Test-Path ".\players.json") {
  Write-Host "  players.json already exists - leaving it as-is (not overwritten)" -ForegroundColor Yellow
} else {
  $content_players_json = @'
{
  "players": [
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
  ]
}

'@
  Set-Content -Path ".\players.json" -Value $content_players_json -NoNewline
  Write-Host "  wrote players.json (starter file)" -ForegroundColor Green
}

$content_add_player_ps1 = @'
# add-player.ps1
# Interactive helper: paste the 4 URLs (+ name + playerId) for ONE player,
# appends a correctly-formatted entry to players.json. Run once per player.
#
# playerId = the EA official ID - the number that appears in BOTH the
# fut.gg URL (.../26-231747/) and the futnext URL (.../231747)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: players.json not found in current folder. Run from scraper-toolkit\." -ForegroundColor Red
  exit 1
}

Write-Host "--- Add a new player ---" -ForegroundColor Cyan
$playerName = Read-Host "Player name (e.g. Kylian Mbappe)"
$playerId   = Read-Host "Player ID (from fut.gg or futnext URL)"
$futbinUrl  = Read-Host "FUTBIN URL"
$futggUrl   = Read-Host "FUT.GG URL"
$futwizUrl  = Read-Host "FUTWIZ URL"
$futnextUrl = Read-Host "FutNext URL"

$json = Get-Content ".\players.json" -Raw | ConvertFrom-Json

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

$existingIds = $json.players | ForEach-Object { $_.playerId }
if ($existingIds -contains $playerId) {
  Write-Host "WARNING: playerId $playerId already exists in players.json - adding anyway (you may want to remove the duplicate manually)." -ForegroundColor Yellow
}

$json.players = @($json.players) + $newPlayer
$json | ConvertTo-Json -Depth 10 | Set-Content ".\players.json" -Encoding UTF8

Write-Host "`nAdded $playerName (id=$playerId). Total players: $($json.players.Count)" -ForegroundColor Green
Write-Host "Run .\add-player.ps1 again for the next player." -ForegroundColor Yellow

'@
Set-Content -Path ".\add-player.ps1" -Value $content_add_player_ps1 -NoNewline
Write-Host "  wrote add-player.ps1" -ForegroundColor Green

New-Item -ItemType Directory -Path "..\scripts" -Force | Out-Null
if (-not (Test-Path "..\scripts\git-checkpoint.ps1")) {
  $content_git_checkpoint = @'
param(
  [Parameter(Mandatory=$true)]
  [string]$Message
)

# Fix Windows "dubious ownership" issue (safe to run every time)
$repoPath = (Get-Location).Path
git config --global --add safe.directory $repoPath | Out-Null

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
  Write-Host "  wrote ..\scripts\git-checkpoint.ps1" -ForegroundColor Green
}

Write-Host ""
Write-Host "Files written. Testing before commit..." -ForegroundColor Cyan
Write-Host "  Run: node index.js" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "feat: FUTBIN top-5 prices, composite merge, JSON store, get/refresh CLI, add-player helper"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}