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
        const date = cells[0]?.textContent.trim() || null;
        const listedFor = num(cells[1]?.textContent);
        const soldFor = num(cells[2]?.textContent);
        const eaTax = num(cells[3]?.textContent);
        const netPrice = num(cells[4]?.textContent);
        const iconEl = cells[5]?.querySelector('i');
        const iconClass = iconEl?.className || '';

        let type;
        if (!soldFor || soldFor === 0) type = 'expired';
        else if (iconClass.includes('bin-icon')) type = 'bin';
        else type = 'bid';

        return { date, listedFor, soldFor, eaTax, netPrice, type };
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

    const result = {
      source: 'FUTBIN_SALES',
      rows,
      salesPerHourEstimate,
      binCount,
      bidCount,
      expiredCount,
      sampleSize: rows.length,
      url,
      timestamp: new Date().toISOString(),
    };

    console.log(`    ✅ FUTBIN sales history: ${rows.length} rows, ~${salesPerHourEstimate ?? '?'} sales/hr (${binCount} bin, ${bidCount} bid, ${expiredCount} expired)`);
    return result;

  } catch (error) {
    console.error(`    ❌ FUTBIN sales history Error:`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape, scrapeSalesHistory };
