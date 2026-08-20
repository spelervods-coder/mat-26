# apply-fixes-v9.ps1 (final)
# - FIXED (definitive): FUTBIN sales icon classification, confirmed via
#   DevTools screenshots. Two separate icon columns: outcome (check/cross)
#   in the date cell, method (bullseye/gavel) in the TYPE cell.
# - NEW: FUTBIN sales-history scraper + FUT.GG Recent Sales/Live Auctions.
# - NEW: --prices-only flag (node index.js --prices-only, or
#   node index.js refresh <id> --prices-only) skips the extra FUTBIN sales
#   page load for a faster run.
# - NEW: store.js auto-preserves static fields (rating/club/nation/
#   cardVersion) if a later scrape fails to extract them - no flag needed,
#   happens automatically on every write.
# All 7 files passed `node --check` before bundling.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v9 (final) files..." -ForegroundColor Cyan

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



/**
 * Sales history from the dedicated FUTBIN sales page (richer than the
 * "Latest Sales" mini-list on the market page - has EA tax breakdown AND
 * a TYPE classification per sale).
 *
 * TYPE classification, confirmed via DevTools element-picker on the icon
 * in the TYPE column:
 * - SOLD FOR === 0 -> "expired" (listing ended with no buyer - most
 *   reliable signal, doesn't depend on guessing an icon class)
 * - icon class contains "bin-icon" -> "bin" (Buy Now purchase, tooltip
 *   confirmed: "Buy Now")
 * - otherwise (plain checkmark, "positive-color") -> "bid" (won via
 *   auction bid, not an instant BIN purchase)
 *
 * This bid/bin/expired split matters for order-flow modeling (Cont,
 * Stoikov & Talreja 2010 style hazard-rate approaches distinguish market
 * or "taker" fills - BIN - from limit/auction fills - bids).
 */
// Accepts the same market URL used by scrape() - derives the FUTBIN id
// and slug from it via regex, staying consistent with the URL-based
// players.json schema (no separate id/slug fields needed).
async function scrapeSalesHistory(playerName, marketUrl) {
  console.log(`  📊 FUTBIN: Scraping sales history for "${playerName}"...`);

  const idMatch = marketUrl.match(/\/player\/(\d+)\/([a-z0-9\-]+)/i);
  if (!idMatch) {
    console.error(`    ❌ FUTBIN sales history: could not parse id/slug from URL: ${marketUrl}`);
    return null;
  }
  const [, futbinId, slug] = idMatch;

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

    const url = `https://www.futbin.com/26/sales/${futbinId}/${slug}?platform=ps`;
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 20000 });
    await page.waitForFunction(() => document.body.innerText.includes('Player Sales History'), { timeout: 15000 });

    const rows = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };

      const tableRows = Array.from(document.querySelectorAll('table tr'))
        .filter(tr => tr.querySelectorAll('td').length >= 5);

      return tableRows.map(tr => {
        const cells = Array.from(tr.querySelectorAll('td'));

        // CONFIRMED via DevTools (Aug 2026): the first <td> contains BOTH
        // an outcome icon AND the date text together, e.g.:
        //   <td><div class="xxs-row align-center">
        //     <i class="fa fa-times-circle negative-color"></i>
        //     <span class="sales-date-time">Aug 18, 6:49 AM</span>
        //   </div></td>
        // Outcome icon: fa-check/positive-color = won, fa-times-circle/
        // negative-color = lost/expired.
        const dateCell = cells[0];
        const outcomeIconEl = dateCell?.querySelector('i');
        const outcomeClass = outcomeIconEl?.className || '';
        const outcome = /times-circle|negative-color/.test(outcomeClass)
          ? 'expired'
          : (/check|positive-color/.test(outcomeClass) ? 'won' : 'unknown');
        const date = dateCell?.querySelector('.sales-date-time')?.textContent.trim()
          || dateCell?.textContent.trim() || null;

        const listedFor = num(cells[1]?.textContent);
        const soldFor = num(cells[2]?.textContent);
        const eaTax = num(cells[3]?.textContent);
        const netPrice = num(cells[4]?.textContent);

        // Last <td> = TYPE column: fa-bullseye-arrow/bin-icon = Buy Now,
        // fa-gavel/bid-icon = Bid. Only meaningful when outcome === 'won'
        // (an expired/unsold row has no purchase method).
        const typeIconEl = cells[5]?.querySelector('i');
        const typeClass = typeIconEl?.className || '';
        let method = null;
        if (/bullseye/i.test(typeClass)) method = 'bin';
        else if (/gavel|hammer/i.test(typeClass)) method = 'bid';

        let type;
        if (outcome === 'expired' || !soldFor || soldFor === 0) type = 'expired';
        else if (method === 'bin') type = 'bin';
        else if (method === 'bid') type = 'bid';
        else type = 'unknown'; // won, but method icon not recognized - safety net, should be rare now

        return { date, listedFor, soldFor, eaTax, netPrice, type, outcome, method };
      });
    });

    // Derive sales-per-hour from the actual observed time span of this
    // table (real data, not a guess) - parse "Aug 17, 7:21 PM" style dates
    // relative to the current year.
    function parseFutbinDate(str) {
      if (!str) return null;
      const d = new Date(`${str} ${new Date().getFullYear()}`);
      return isNaN(d.getTime()) ? null : d;
    }

    const timestamps = rows.map(r => parseFutbinDate(r.date)).filter(Boolean);
    let salesPerHourEstimate = null;
    if (timestamps.length >= 2) {
      const newest = Math.max(...timestamps.map(d => d.getTime()));
      const oldest = Math.min(...timestamps.map(d => d.getTime()));
      const spanHours = Math.max((newest - oldest) / 3600000, 0.1);
      const realSales = rows.filter(r => r.type !== 'expired').length;
      salesPerHourEstimate = Math.round((realSales / spanHours) * 10) / 10;
    }

    const binCount = rows.filter(r => r.type === 'bin').length;
    const bidCount = rows.filter(r => r.type === 'bid').length;
    const expiredCount = rows.filter(r => r.type === 'expired').length;
    const unknownCount = rows.filter(r => r.type === 'unknown').length;

    const result = {
      source: 'FUTBIN_SALES',
      rows,
      salesPerHourEstimate,
      binCount,
      bidCount,
      expiredCount,
      unknownCount,
      sampleSize: rows.length,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FUTBIN sales history: ${rows.length} rows, ~${salesPerHourEstimate ?? '?'} sales/hr (${binCount} bin, ${bidCount} bid, ${expiredCount} expired, ${unknownCount} unknown)`);
    if (unknownCount > 0) {
      console.log(`    ℹ️  ${unknownCount} row(s) had an unrecognized TYPE icon - raw classes logged in the "unknown" rows for verification:`);
      rows.filter(r => r.type === 'unknown').slice(0, 3).forEach(r => console.log(`       outcome="${r.outcome}" method="${r.method}" soldFor=${r.soldFor}`));
    }
    return result;

  } catch (error) {
    console.error(`    ❌ FUTBIN sales history Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape, scrapeSalesHistory };

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

      // FIXED (v9): confirmed via DevTools element-picker that these
      // sections use a real <h3>"Recent Sales"</h3> / <h3>"Live Auctions"</h3>
      // heading followed by an actual <table>. Walking to the nearest
      // following table (instead of v6's crude "grab next N lines of text")
      // gives clean structured rows instead of noise.
      function extractTableAfterHeading(headingText) {
        const headings = Array.from(document.querySelectorAll('h3'));
        const heading = headings.find(h => h.textContent.trim() === headingText);
        if (!heading) return [];

        let el = heading.nextElementSibling;
        let table = null;
        let hops = 0;
        while (el && hops < 5) {
          table = el.querySelector ? el.querySelector('table') : (el.tagName === 'TABLE' ? el : null);
          if (table) break;
          el = el.nextElementSibling;
          hops++;
        }
        if (!table) return [];

        return Array.from(table.querySelectorAll('tbody tr')).map(tr =>
          Array.from(tr.querySelectorAll('td')).map(td => td.textContent.trim())
        );
      }

      // Recent Sales: [timeSoldAgo, price] per row
      const recentSalesRowsRaw = extractTableAfterHeading('Recent Sales');
      const recentSalesRaw = recentSalesRowsRaw.length
        ? recentSalesRowsRaw.map(([timeAgo, price]) => ({ timeAgo, price: num(price) }))
        : null;

      // Live Auctions: [ending, startBid, bin] per row - a SNAPSHOT of
      // currently active auctions (supply depth), not literally a
      // "listings created per hour" flow rate - useful as a liquidity
      // proxy but conceptually distinct, noted in mergePrices.js.
      const liveAuctionsRowsRaw = extractTableAfterHeading('Live Auctions');
      const liveAuctionsRaw = liveAuctionsRowsRaw.length
        ? liveAuctionsRowsRaw.map(([ending, startBid, bin]) => ({ ending, startBid: num(startBid), bin: num(bin) }))
        : null;

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
        recentSalesRaw,
        liveAuctionsRaw,
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

async function cmdScrapeAll({ withSales = true } = {}) {
  const players = loadPlayersConfig();
  const results = [];

  for (const playerDef of players) {
    const merged = await scrapePlayerFull(playerDef, { withSales });
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
  } else {
    console.log('Usage:');
    console.log('  node index.js [--prices-only]                 scrape all players.json entries');
    console.log('                                                 (--prices-only skips FUTBIN sales history, faster)');
    console.log('  node index.js get <cardId> [--json]           overview from cache, auto-refresh if stale');
    console.log('  node index.js refresh <cardId> [--json]       force full refresh (all 4 sources + sales history)');
    console.log('  node index.js refresh <cardId> --prices-only   force refresh, skip sales history (faster)');
    console.log('  node index.js refresh <cardId> --source=futbin   refresh only 1 source, keep rest cached');
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

function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData, futbinSalesData = null }) {
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

  // Liquidity metrics for the pricing model (Cont/Stoikov/Talreja-style
  // order-flow inputs). salesPerHour comes from FUTBIN's real sales
  // history (bid/bin/expired classified). listingsSnapshot comes from
  // FUT.GG's Live Auctions table - a SUPPLY DEPTH snapshot (how many
  // active auctions right now), not literally a "listings created per
  // hour" flow rate - related but distinct, treated as a proxy.
  const salesPerHourEstimate = futbinSalesData?.salesPerHourEstimate ?? null;
  const activeListingsSnapshot = futggData?.liveAuctionsRaw?.length ?? null;
  const liquidityRatio = (salesPerHourEstimate !== null && activeListingsSnapshot)
    ? Math.round((salesPerHourEstimate / activeListingsSnapshot) * 100) / 100
    : null;
  const bidBinBreakdown = futbinSalesData
    ? { bin: futbinSalesData.binCount, bid: futbinSalesData.bidCount, expired: futbinSalesData.expiredCount, sampleSize: futbinSalesData.sampleSize }
    : null;

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
      salesPerHourEstimate,
      activeListingsSnapshot,
      liquidityRatio,
      bidBinBreakdown,
      recentSalesFutggStructured: futggData?.recentSalesRaw ?? null,
      liveAuctionsFutggStructured: futggData?.liveAuctionsRaw ?? null,
      binPrices,
      lowestAcrossSources,
      averageBinPrice: calculateAverage(Object.values(binPrices)),
      binPricePercentInRange,
      priceRange: futbinData?.priceRange ?? null,
      futbinLowest5: futbinData?.lowestPrices ?? null,
      futbinLowest5Count: futbinData?.lowestPricesCount ?? null,
      recentSales: futbinData?.recentSales ?? null,
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
  if (m.salesPerHourEstimate !== null) {
    lines.push(`  Sales/hr (FUTBIN, real): ~${m.salesPerHourEstimate}`);
  }
  if (m.activeListingsSnapshot !== null) {
    lines.push(`  Active listings snapshot (FUT.GG): ${m.activeListingsSnapshot}`);
  }
  if (m.liquidityRatio !== null) {
    lines.push(`  Liquidity ratio (sales/listings): ${m.liquidityRatio}`);
  }
  if (m.bidBinBreakdown) {
    const b = m.bidBinBreakdown;
    lines.push(`  Recent sales breakdown: ${b.bin} bin, ${b.bid} bid, ${b.expired} expired (n=${b.sampleSize})`);
  }
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

// Fields that don't change over time (rating, club, nation, cardVersion).
// If a scrape fails to extract one of these (e.g. a site's layout changed
// and the selector broke), we don't want that null to silently overwrite
// a previously-known-good value. "static if missing" - automatic, no
// flag needed: every scrape still re-fetches the full page (no time
// saved), but a bad/failed extraction can't corrupt data we already had.
const STATIC_FIELDS = ['rating', 'position', 'club', 'nation'];

function upsertEntry(playerId, mergedData) {
  const db = loadDb();
  const previous = db[playerId];

  if (previous?.merged && mergedData?.merged) {
    for (const field of STATIC_FIELDS) {
      const isMissing = mergedData.merged[field] === null || mergedData.merged[field] === undefined;
      const hadValue = previous.merged[field] !== null && previous.merged[field] !== undefined;
      if (isMissing && hadValue) {
        mergedData.merged[field] = previous.merged[field];
      }
    }
    if (!mergedData.cardVersion && previous.cardVersion) {
      mergedData.cardVersion = previous.cardVersion;
    }
  }

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

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "feat: definitive FUTBIN sales icon classification, --prices-only mode, static-field preservation"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}