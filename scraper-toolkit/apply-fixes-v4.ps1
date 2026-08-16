# apply-fixes-v4.ps1
# Adds: cardVersion (all 4 sources, with mismatch check), FUTBIN
# priceRange fix + recentSales, binPricePercentInRange, FUT.GG experimental
# recent-sales/live-auctions, and a pretty formatOverview() used by 'get'.
# Auto-commits + pushes to git at the end.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v4 files..." -ForegroundColor Cyan

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

$content_futgg_scraper_js = @'
/**
 * FUT.GG SCRAPER (v4)
 *
 * NEW:
 * - cardVersion: from the explicit "Rarity" field in Player Information
 *   (confirmed via direct fetch: "Rarity ... Rare" - clean structured text).
 * - recentSales / liveAuctions: EXPERIMENTAL / best-effort. Confirmed via
 *   direct fetch that this content is NOT present even as an empty
 *   skeleton in server HTML - it's built client-side, likely only after
 *   scrolling into view. We scroll + wait + try to read it; if the
 *   section never appears, these fields come back as null/[] rather than
 *   crashing. If this is consistently empty, send a DevTools element-pick
 *   screenshot of that section (like we did for BIN price) and it can be
 *   made reliable.
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
    await page.waitForFunction(() => document.body.innerText.includes('Lowest BIN'), { timeout: 15000 });

    // Best-effort: scroll to #prices section and give client-side content
    // a moment to mount, in case Recent Sales / Live Auctions load lazily.
    try {
      await page.evaluate(() => {
        const el = document.getElementById('prices');
        if (el) el.scrollIntoView();
      });
      await new Promise(r => setTimeout(r, 1500));
    } catch (_) { /* non-fatal */ }

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };

      function findValueAfterLabel(labelText) {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
        let foundLabel = false, node;
        while ((node = walker.nextNode())) {
          if (!foundLabel) {
            if (node.children.length === 0 && node.textContent.trim() === labelText) foundLabel = true;
            continue;
          }
          if (node.matches && node.matches('span.tabular-nums')) return node.textContent;
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
      const rarityMatch = bodyText.match(/Rarity\s*\n?\s*([A-Za-z][A-Za-z\s]*?)\n/i);
      const momentumMatch = bodyText.match(/Lowest\s*\n?\s*([\d,]+)\s*\n?\s*Average\s*\n?\s*([\d,]+)\s*\n?\s*Highest\s*\n?\s*([\d,]+)/i);

      // Experimental: look for a "Recent Sales" / "Live Auctions" heading
      // and grab a handful of lines after it. Returns [] if not found.
      function extractSectionRows(heading, maxRows = 10) {
        const idx = bodyText.indexOf(heading);
        if (idx === -1) return [];
        const chunk = bodyText.slice(idx + heading.length, idx + heading.length + 800);
        const lines = chunk.split('\n').map(l => l.trim()).filter(Boolean).slice(0, maxRows);
        return lines;
      }
      const recentSalesRaw = extractSectionRows('Recent Sales');
      const liveAuctionsRaw = extractSectionRows('Live Auctions');

      return {
        lowestBin,
        rating: ratingMatch ? num(ratingMatch[1]) : null,
        position: ratingMatch ? ratingMatch[2] : null,
        club: clubMatch ? clubMatch[1].trim() : null,
        nation: nationMatch ? nationMatch[1].trim() : null,
        cardVersion: rarityMatch ? rarityMatch[1].trim() : null,
        playerId: playerIdMatch ? playerIdMatch[1] : null,
        itemId: itemIdMatch ? itemIdMatch[1] : null,
        priceMomentum: momentumMatch
          ? { lowest: num(momentumMatch[1]), average: num(momentumMatch[2]), highest: num(momentumMatch[3]) }
          : null,
        recentSalesRaw: recentSalesRaw.length ? recentSalesRaw : null,
        liveAuctionsRaw: liveAuctionsRaw.length ? liveAuctionsRaw : null,
      };
    });

    const result = { source: 'FUT.GG', name: playerName, ...data, url, timestamp: new Date().toISOString() };
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
 * FUTWIZ SCRAPER (v4)
 *
 * NEW: cardVersion - verified via direct fetch, two sources agree:
 * - document.title: "Kylian Mbappe EA FC26 Gold Rare - rated 91"
 * - explicit "Version" field in the attribute list
 * Title regex used as primary (simpler), Version-field regex as fallback.
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

      const titleMatch = document.title.match(/EA FC\d+\s+(.+?)\s*-\s*rated/i);
      const versionFieldMatch = bodyText.match(/Version\s*\n+\s*([A-Za-z][A-Za-z\s]*?)\n/i);
      const cardVersion = titleMatch ? titleMatch[1].trim() : (versionFieldMatch ? versionFieldMatch[1].trim() : null);

      return {
        marketValue,
        cardId: cardIdMatch ? cardIdMatch[1] : null,
        playerId: playerIdMatch ? playerIdMatch[1] : null,
        added: addedMatch ? addedMatch[1].trim().split('\n')[0] : null,
        likesPercent: likesMatch ? parseInt(likesMatch[1], 10) : null,
        cardVersion,
      };
    });

    const result = { source: 'FUTWIZ', ...data, url, timestamp: new Date().toISOString() };
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
 * FUTNEXT SCRAPER (v4)
 *
 * NEW: cardVersion - verified via direct fetch:
 * - document.title: "Kylian Mbappé Rare EA FC 26 - FUTNEXT"
 * - h3 heading: "Kylian Mbappé - Rare" (fallback)
 * Also confirmed: when no sales exist, page shows literal
 * "No data to show" / "Recent sales are not available" - handled
 * gracefully (returns null, not a crash).
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
    await page.waitForFunction(() => document.body.innerText.includes('Lowest'), { timeout: 15000 });

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

      const titleMatch = document.title.match(/^.*?\s+(.+?)\s+EA FC\s*\d+/i);
      const cardVersion = titleMatch ? titleMatch[1].trim() : null;

      const hasRecentSales = !bodyText.includes('Recent sales are not available');
      const recentSalesNote = hasRecentSales ? null : 'not available';

      return {
        currentCheapest: cheapestMatch ? num(cheapestMatch[1]) : lowest24hMatch ? num(lowest24hMatch[1]) : null,
        lowest24h: lowest24hMatch ? num(lowest24hMatch[1]) : null,
        average24h: avg24hMatch ? num(avg24hMatch[1]) : null,
        change24h: changeMatch ? { amount: num(changeMatch[1]), percent: parseFloat(changeMatch[2]) } : null,
        cardVersion,
        recentSalesNote,
      };
    });

    const result = { source: 'FutNext', ...data, url, timestamp: new Date().toISOString() };
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
 * FC26 SCRAPER ORCHESTRATOR (v4)
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

  return mergePrices({ playerName, futbinData, futggData, futwizData, futnextData });
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
    const freshData = await scrapeSource(source, playerDef.playerName, playerDef.urls[source]);
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
  lines.push(`Last updated: ${m.lastUpdated}`);
  return lines.join('\n');
}

module.exports = { mergePrices, formatOverview };

'@
Set-Content -Path ".\mergePrices.js" -Value $content_mergePrices_js -NoNewline
Write-Host "  wrote mergePrices.js" -ForegroundColor Green

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host "  Test: node index.js get 231747" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "feat: cardVersion, price-range %, recent sales, pretty overview"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}