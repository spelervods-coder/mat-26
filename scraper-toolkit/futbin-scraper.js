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
