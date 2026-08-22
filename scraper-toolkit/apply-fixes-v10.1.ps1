# apply-fixes-v10.1.ps1 (SELF-CONTAINED)
#
# BUG FIX (urgent, was blocking everything):
# - players.json had a UTF-8 BOM (from PowerShell's Set-Content -Encoding
#   UTF8, which always adds one on Windows PowerShell 5.1), breaking
#   JSON.parse with 'Unexpected token'. Fixed on both sides: index.js now
#   strips a BOM defensively if present, AND add-player.ps1/
#   manage-players.ps1 now write via [System.IO.File]::WriteAllText with
#   an explicit no-BOM UTF8Encoding, so it won't happen again.
#
# NEW:
# - TOS score now shown after every get/refresh/scrape-all overview, not
#   just at buy-time.
# - 'node index.js scores' - ranks all players.json entries by cached TOS,
#   for quickly screening a big batch of candidates.
# - FIFO resolution: list/sold/expired/relist now accept a cardId (not just
#   positionId) - auto-picks the oldest position in the right state, since
#   cards of the same cardId are fungible (EA doesn't track which literal
#   instance you act on).
# - watch-positions.ps1 - separate terminal, alerts you (Windows toast via
#   BurntToast if installed, else a beep) when a listing crosses 60 minutes.
#
# All JS files passed `node --check` before bundling.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\players.json")) {
  Write-Host "ERROR: run this from inside the scraper-toolkit folder." -ForegroundColor Red
  exit 1
}

Write-Host "Writing v10.1 files (self-contained)..." -ForegroundColor Cyan

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

    // Derive rates from the actual observed time span of this table (real
    // data, not a guess) - parse "Aug 17, 7:21 PM" style dates relative
    // to the current year.
    function parseFutbinDate(str) {
      if (!str) return null;
      const d = new Date(`${str} ${new Date().getFullYear()}`);
      return isNaN(d.getTime()) ? null : d;
    }

    const timestamps = rows.map(r => parseFutbinDate(r.date)).filter(Boolean);
    let salesPerHourEstimate = null;
    let listingsPerHourEstimate = null;
    if (timestamps.length >= 2) {
      const newest = Math.max(...timestamps.map(d => d.getTime()));
      const oldest = Math.min(...timestamps.map(d => d.getTime()));
      const spanHours = Math.max((newest - oldest) / 3600000, 0.1);
      const realSales = rows.filter(r => r.type !== 'expired').length;
      salesPerHourEstimate = Math.round((realSales / spanHours) * 10) / 10;
      // NEW: listings/hour = ALL resolved rows (sold + expired) in this
      // same table - this table already gives us both sides (sales AND
      // listings), no need for FUT.GG's Live Auctions snapshot for this.
      listingsPerHourEstimate = Math.round((rows.length / spanHours) * 10) / 10;
    }

    const binCount = rows.filter(r => r.type === 'bin').length;
    const bidCount = rows.filter(r => r.type === 'bid').length;
    const expiredCount = rows.filter(r => r.type === 'expired').length;
    const unknownCount = rows.filter(r => r.type === 'unknown').length;

    const result = {
      source: 'FUTBIN_SALES',
      rows,
      salesPerHourEstimate,
      listingsPerHourEstimate,
      binCount,
      bidCount,
      expiredCount,
      unknownCount,
      sampleSize: rows.length,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FUTBIN sales history: ${rows.length} rows, ~${salesPerHourEstimate ?? '?'} sales/hr, ~${listingsPerHourEstimate ?? '?'} listings/hr (${binCount} bin, ${bidCount} bid, ${expiredCount} expired, ${unknownCount} unknown)`);
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
 * FUTNEXT SCRAPER (v6)
 *
 * FIXED cardVersion: old regex assumed the name was a single word before
 * the rarity, but titles are "<Full Name> <Version> EA FC <year> - FUTNEXT"
 * - with a multi-word name this captured too much ("Mbappé Rare" instead
 *   of "Rare"). Now strips the KNOWN playerName from the title first
 *   (passed in from the caller), leaving only the version.
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

    const data = await page.evaluate((playerNameArg) => {
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

      // FIXED: strip the known player name from the title, leaving only the version
      let cardVersion = null;
      const escapedName = playerNameArg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const nameStripRe = new RegExp(escapedName + '\\s+(.+?)\\s+EA FC', 'i');
      const titleMatch = document.title.match(nameStripRe);
      if (titleMatch) {
        cardVersion = titleMatch[1].trim();
      } else {
        // fallback: generic pattern if the exact name doesn't match (e.g. accents differ)
        const genericMatch = document.title.match(/\s(.+?)\s+EA FC\s*\d+/i);
        cardVersion = genericMatch ? genericMatch[1].trim() : null;
      }

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
    }, playerName);

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
  // order-flow inputs). FIXED: both salesPerHour AND listingsPerHour now
  // come from the SAME source (FUTBIN's sales-history table already
  // contains every resolved listing - sold AND expired - so we don't
  // need FUT.GG's Live Auctions as a mismatched proxy anymore). This is
  // more consistent than mixing two different sites/timeframes.
  const salesPerHourEstimate = futbinSalesData?.salesPerHourEstimate ?? null;
  const listingsPerHourEstimate = futbinSalesData?.listingsPerHourEstimate ?? null;
  const marketLiquidityRatio = (salesPerHourEstimate !== null && listingsPerHourEstimate)
    ? Math.round((salesPerHourEstimate / listingsPerHourEstimate) * 100) / 100
    : null;
  const bidBinBreakdown = futbinSalesData
    ? { bin: futbinSalesData.binCount, bid: futbinSalesData.bidCount, expired: futbinSalesData.expiredCount, sampleSize: futbinSalesData.sampleSize }
    : null;
  // FUT.GG Live Auctions kept SEPARATE - advisory only ("these auctions
  // look interesting"), never used as an engine input (see report §3).
  const activeAuctionsSnapshot = futggData?.liveAuctionsRaw ?? null;

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
      listingsPerHourEstimate,
      marketLiquidityRatio,
      bidBinBreakdown,
      activeAuctionsSnapshot, // advisory only, see comment above
      recentSalesFutggStructured: futggData?.recentSalesRaw ?? null,
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
  if (m.listingsPerHourEstimate !== null) {
    lines.push(`  Listings/hr (FUTBIN, real): ~${m.listingsPerHourEstimate}`);
  }
  if (m.marketLiquidityRatio !== null) {
    lines.push(`  Market liquidity ratio (sales/listings): ${m.marketLiquidityRatio}`);
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

$content_pricing_engine_js = @'
/**
 * PRICING ENGINE (v1, shadow-mode-ready)
 *
 * Implements the Hybrid TOS scoring approach from PRICING_STRATEGY.md,
 * adapted to the fields our scrapers actually produce. TOS weights
 * (35/30/20/15) are v1 arbitrary starting values - recalibrate via
 * logistic regression once 20-30 closed positions exist (report §5.2,
 * Fase C) - NEVER auto-adjusted silently, always in overleg.
 */

const EA_TAX = 0.05;

// --- Slot capacity pressure (report §6.2) ---
// 0-40: no pressure. 40-90: linear ramp. 90-97: steep. 97-100: blocked.
// Midpoint ~82 so pressure is already strong by 95-97 (per feedback:
// "heel moeilijk om boven de 95-97 te komen").
function slotPressureMultiplier(activeSlots) {
  if (activeSlots <= 40) return 1.0;
  if (activeSlots >= 97) return 0.0; // no new buy recommendations at all
  if (activeSlots <= 90) {
    const t = (activeSlots - 40) / (90 - 40);
    return 1.0 - t * 0.6; // 1.0 -> 0.4
  }
  const t = (activeSlots - 90) / (97 - 90);
  return 0.4 - t * 0.35; // 0.4 -> 0.05
}

// --- Max cards of the same cardId (report §6) ---
// hardCap default 4 (proposed: less concentration risk than 5, more
// upside room than 3 - adjustable in overleg once we see real outcomes).
function maxCardsForPlayer(accountBudget, buyPrice, { maxPct = 0.125, hardCap = 4 } = {}) {
  const pctCap = buyPrice > 0 ? Math.floor((accountBudget * maxPct) / buyPrice) : 0;
  return Math.max(0, Math.min(pctCap, hardCap));
}

// --- FC26 price ticks ---
function roundToTick(price) {
  const tick = price < 50000 ? 250 : 500;
  return Math.round(price / tick) * tick;
}

// --- TOS sub-scores (0-10 each) ---
function profitPotentialScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  return Math.max(0, Math.min(10, 10 - pct / 10)); // lower in range = more upside
}

function liquidityScore(merged) {
  const ratio = merged.marketLiquidityRatio;
  if (ratio === null || ratio === undefined) return 5; // unknown -> neutral, don't fake confidence
  return Math.max(0, Math.min(10, ratio * 5)); // ratio ~1.0 balanced -> score 5
}

function meanReversionScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  if (pct <= 50) return Math.min(10, 5 + (50 - pct) / 5);
  return Math.max(0, 5 - (pct - 50) / 10);
}

function rangePositionScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  return Math.max(0, Math.min(10, 10 - pct / 10));
}

const TOS_WEIGHTS = { profit: 0.35, liquidity: 0.30, meanReversion: 0.20, range: 0.15 };

function calculateTOS(merged) {
  const profit = profitPotentialScore(merged);
  const liquidity = liquidityScore(merged);
  const meanReversion = meanReversionScore(merged);
  const range = rangePositionScore(merged);

  const tos = profit * TOS_WEIGHTS.profit
    + liquidity * TOS_WEIGHTS.liquidity
    + meanReversion * TOS_WEIGHTS.meanReversion
    + range * TOS_WEIGHTS.range;

  return {
    tos: Math.round(tos * 10) / 10,
    subScores: { profit, liquidity, meanReversion, range },
    weights: { ...TOS_WEIGHTS },
  };
}

// --- Buy/sell price recommendation ---
const RISK_PROFILES = {
  conservative: { minMarginPct: 0.10 },
  standard: { minMarginPct: 0.06 },
  aggressive: { minMarginPct: 0.03 },
};

function recommendPrices(merged, {
  riskProfile = 'standard',
  activeSlots = 0,
  inventoryQ = 0,
} = {}) {
  const profile = RISK_PROFILES[riskProfile] || RISK_PROFILES.standard;
  const bin = merged.lowestAcrossSources?.price ?? merged.averageBinPrice;
  if (!bin) return null;

  const pressure = slotPressureMultiplier(activeSlots);
  // Slot pressure LOWERS the margin requirement (prioritize turnover
  // when the transfer list is nearly full) - report §2.3/§6.2.
  const marginPct = Math.max(0.02, profile.minMarginPct * (0.4 + 0.6 * pressure));

  // Inventory penalty (Avellaneda-Stoikov style soft dampening) - more
  // of this card already held -> aim for a slightly lower sell price to
  // move it faster.
  const inventoryPenalty = Math.max(0.5, 1 - 0.03 * inventoryQ);

  const sellPrice = roundToTick(bin * inventoryPenalty);
  const netRevenue = sellPrice * (1 - EA_TAX);
  const buyPrice = roundToTick(netRevenue / (1 + marginPct));

  const expectedProfit = Math.round(netRevenue - buyPrice);
  const expectedRoiPct = buyPrice > 0 ? Math.round((expectedProfit / buyPrice) * 1000) / 10 : 0;

  return {
    buyPrice,
    sellPrice,
    expectedProfit,
    expectedRoiPct,
    marginPctUsed: Math.round(marginPct * 1000) / 10,
    slotPressure: Math.round(pressure * 100) / 100,
  };
}

// --- Relist price: RE-RUNS the engine with FRESH data (not a fixed
// decrement of the old price - market may have moved either direction
// since the original listing, per feedback). A single-step cap prevents
// overreacting to one noisy scrape.
function recommendRelistPrice(merged, previousListPrice, opts = {}) {
  const fresh = recommendPrices(merged, opts);
  if (!fresh) return null;

  const maxStepPct = 0.15; // never move more than 15% in one relist step
  const floor = previousListPrice * (1 - maxStepPct);
  const ceiling = previousListPrice * (1 + maxStepPct);
  const cappedSellPrice = roundToTick(Math.max(floor, Math.min(fresh.sellPrice, ceiling)));

  return { ...fresh, sellPrice: cappedSellPrice, previousListPrice, wasCapped: cappedSellPrice !== fresh.sellPrice };
}

module.exports = {
  EA_TAX,
  slotPressureMultiplier,
  maxCardsForPlayer,
  roundToTick,
  calculateTOS,
  recommendPrices,
  recommendRelistPrice,
  RISK_PROFILES,
};

'@
Set-Content -Path ".\pricing-engine.js" -Value $content_pricing_engine_js -NoNewline
Write-Host "  wrote pricing-engine.js" -ForegroundColor Green

$content_positions_store_js = @'
/**
 * POSITION TRACKING (report §6.1, §7.1)
 *
 * One positionId per BOUGHT card instance - NOT per cardId. A cardId
 * (e.g. Mbappé Gold Rare) can have several open positions at once if
 * you bought multiple copies at different times/prices.
 *
 * Stored as a single JSON object keyed by positionId (like players-db.json)
 * rather than JSONL, because positions get UPDATED over their lifecycle
 * (buy -> list -> expire -> relist -> sold), not just appended once.
 *
 * IMPORTANT (corrected per user feedback): EA does NOT automatically
 * return an expired listing to your club - it stays on the transfer
 * list until you manually collect it. So "expired" positions still
 * count toward your 100-slot limit until you take further action.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const POSITIONS_FILE = path.join(process.env.OUTPUT_DIR || './output', 'positions.json');

function loadPositions() {
  if (!fs.existsSync(POSITIONS_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(POSITIONS_FILE, 'utf8'));
  } catch (e) {
    console.error('⚠️  Could not parse positions.json:', e.message);
    return {};
  }
}

function savePositions(positions) {
  const dir = path.dirname(POSITIONS_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(POSITIONS_FILE, JSON.stringify(positions, null, 2));
}

function createPosition(cardId, playerName, buyPrice) {
  const positions = loadPositions();
  const positionId = crypto.randomUUID();
  positions[positionId] = {
    positionId,
    cardId,
    playerName,
    events: [{ action: 'buy', price: buyPrice, timestamp: new Date().toISOString() }],
    holdUntil: null,
    relistCount: 0,
    status: 'open', // open | closed | stuck
    finalProfit: null,
  };
  savePositions(positions);
  return positions[positionId];
}

function addEvent(positionId, event) {
  const positions = loadPositions();
  const pos = positions[positionId];
  if (!pos) return null;

  pos.events.push({ ...event, timestamp: new Date().toISOString() });

  if (event.action === 'relist') pos.relistCount = (pos.relistCount || 0) + 1;

  if (event.action === 'sold') {
    pos.status = 'closed';
    const buyEvent = pos.events.find(e => e.action === 'buy');
    const netPrice = event.netPrice ?? Math.round(event.price * 0.95);
    pos.finalProfit = netPrice - (buyEvent?.price ?? 0);
  }

  if (event.action === 'stuck') pos.status = 'stuck';

  savePositions(positions);
  return pos;
}

function getPosition(positionId) {
  return loadPositions()[positionId] || null;
}

function getAllPositions() {
  return Object.values(loadPositions());
}

function getOpenPositions() {
  // "open" here means "still occupying a transfer-list slot" - includes
  // bought-not-listed, listed-not-sold, AND expired-not-yet-relisted
  // (see IMPORTANT note above - EA doesn't auto-clear these).
  return getAllPositions().filter(p => p.status === 'open');
}

function countActiveSlots() {
  return getOpenPositions().length;
}

function countPositionsForCard(cardId) {
  return getOpenPositions().filter(p => String(p.cardId) === String(cardId)).length;
}

function findPositionByPrefix(idPrefix) {
  const positions = loadPositions();
  const match = Object.keys(positions).find(id => id.startsWith(idPrefix));
  return match ? positions[match] : null;
}

// FIFO resolver: cards of the same cardId are fungible (EA doesn't track
// which literal instance you sell) - so when acting "on a cardId" rather
// than a specific positionId, pick the OLDEST open position that's
// currently in one of the allowed states for this action. E.g. you can't
// "sell" a position that hasn't been listed yet.
function findOldestOpenPositionForCard(cardId, allowedLastActions) {
  const candidates = getOpenPositions().filter(p => {
    if (String(p.cardId) !== String(cardId)) return false;
    const lastEvent = p.events[p.events.length - 1];
    return allowedLastActions.includes(lastEvent.action);
  });
  if (!candidates.length) return null;
  candidates.sort((a, b) => new Date(a.events[0].timestamp) - new Date(b.events[0].timestamp));
  return candidates[0];
}

module.exports = {
  createPosition, addEvent, getPosition, getAllPositions, getOpenPositions,
  countActiveSlots, countPositionsForCard, findPositionByPrefix,
  findOldestOpenPositionForCard, POSITIONS_FILE,
};

'@
Set-Content -Path ".\positions-store.js" -Value $content_positions_store_js -NoNewline
Write-Host "  wrote positions-store.js" -ForegroundColor Green

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
$jsonText = $json | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText((Resolve-Path ".\players.json"), $jsonText, (New-Object System.Text.UTF8Encoding $false))

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
  $jsonText = $json | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText((Resolve-Path ".\players.json"), $jsonText, (New-Object System.Text.UTF8Encoding $false))
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

$content_watch_positions_ps1 = @'
# watch-positions.ps1
# Checks output/positions.json every minute for listings older than 60
# minutes that haven't been marked sold/expired yet, and alerts you.
# Uses a real Windows toast notification if the BurntToast module is
# installed, otherwise falls back to a console beep + message (works
# either way - no hard dependency).
#
# Run in a SEPARATE terminal window, alongside scheduler.ps1.
#
# Optioneel voor nette meldingen:
#   Install-Module BurntToast -Scope CurrentUser

param(
  [int]$CheckIntervalSeconds = 60,
  [int]$ListingMinutes = 60
)

$hasBurntToast = Get-Module -ListAvailable -Name BurntToast

function Notify($title, $message) {
  if ($hasBurntToast) {
    Import-Module BurntToast -ErrorAction SilentlyContinue
    New-BurntToastNotification -Text $title, $message
  } else {
    [console]::beep(800, 300)
    Write-Host "`n🔔 $title" -ForegroundColor Yellow
    Write-Host "   $message" -ForegroundColor Yellow
  }
}

Write-Host "Watching positions.json for overdue listings (elke $CheckIntervalSeconds sec, drempel $ListingMinutes min)..." -ForegroundColor Cyan
if (-not $hasBurntToast) {
  Write-Host "Tip: 'Install-Module BurntToast -Scope CurrentUser' voor echte Windows-notificaties i.p.v. alleen een pieptoon." -ForegroundColor Yellow
}
Write-Host "Ctrl+C om te stoppen.`n" -ForegroundColor Cyan

$alreadyNotified = @{}

while ($true) {
  if (Test-Path ".\output\positions.json") {
    try {
      $positions = Get-Content ".\output\positions.json" -Raw | ConvertFrom-Json
      foreach ($prop in $positions.PSObject.Properties) {
        $pos = $prop.Value
        if ($pos.status -ne "open") { continue }
        $lastEvent = $pos.events[-1]
        if ($lastEvent.action -eq "list" -or $lastEvent.action -eq "relist") {
          $listedAt = [datetime]$lastEvent.timestamp
          $minutesAgo = (Get-Date).ToUniversalTime().Subtract($listedAt.ToUniversalTime()).TotalMinutes
          $key = "$($pos.positionId)-$($lastEvent.timestamp)"
          if ($minutesAgo -ge $ListingMinutes -and -not $alreadyNotified.ContainsKey($key)) {
            $shortId = $pos.positionId.Substring(0, 8)
            Notify "Listing verlopen: $($pos.playerName)" "Gelist voor $($lastEvent.price) - check: node index.js sold $($pos.cardId) <prijs>  of  node index.js expired $($pos.cardId)"
            $alreadyNotified[$key] = $true
          }
        }
      }
    } catch {
      Write-Host "⚠️  Kon positions.json niet lezen: $_" -ForegroundColor Red
    }
  }
  Start-Sleep -Seconds $CheckIntervalSeconds
}

'@
Set-Content -Path ".\watch-positions.ps1" -Value $content_watch_positions_ps1 -NoNewline
Write-Host "  wrote watch-positions.ps1" -ForegroundColor Green

Write-Host ""
Write-Host "Files written." -ForegroundColor Cyan
Write-Host ""
Write-Host "Belangrijk: players.json wordt NIET automatisch herschreven door dit" -ForegroundColor Yellow
Write-Host "script (om je 15 spelers niet te overschrijven). Als node index.js nog" -ForegroundColor Yellow
Write-Host "steeds de BOM-fout geeft, herstel het bestand met dit ene commando:" -ForegroundColor Yellow
Write-Host "  `$c = Get-Content .\players.json -Raw; [System.IO.File]::WriteAllText((Resolve-Path .\players.json), `$c, (New-Object System.Text.UTF8Encoding `$false))" -ForegroundColor White
Write-Host ""
Write-Host "Test: node index.js scores" -ForegroundColor Yellow
Write-Host ""
$doCommit = Read-Host "Commit + push these changes to git now? (y/n)"
if ($doCommit -eq "y") {
  Push-Location ..
  .\scripts\git-checkpoint.ps1 -Message "fix: BOM in players.json (blocking bug); add scores command, FIFO position resolution, watch-positions.ps1"
  Pop-Location
} else {
  Write-Host "Skipped commit. Run manually later:" -ForegroundColor Yellow
  Write-Host "  cd .. ; .\scripts\git-checkpoint.ps1 -Message your message"
}