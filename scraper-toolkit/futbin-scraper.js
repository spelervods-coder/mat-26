/**
 * FUTBIN SCRAPER
 *
 * Confirmed selectors (via DevTools element picker, Aug 2026):
 * - BIN price:       .price.inline-with-icon.lowest-price-1
 * - Price range/upd: .price-box-full-width-xxs-column
 * - Market grid:     .market-grid.platform-pc-only (avg BIN, cheapest, EA avg)
 *
 * Prices are client-side rendered - Puppeteer required (confirmed: static
 * fetch returns "0 Coin" / "No Data Available" everywhere).
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, futbinId, slug) {
  console.log(`  📊 FUTBIN: Scraping "${playerName}" (id=${futbinId})...`);

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

    const url = `https://www.futbin.com/26/player/${futbinId}/${slug}/market`;
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 20000 });

    // Wait for the price to actually hydrate (client-side render)
    await page.waitForSelector('.price.inline-with-icon.lowest-price-1', { timeout: 15000 });

    const data = await page.evaluate(() => {
      const num = (t) => {
        if (!t) return null;
        const n = parseInt(t.replace(/[^\d]/g, ''), 10);
        return isNaN(n) ? null : n;
      };
      const clean = (t) => t?.replace(/\s+/g, ' ').trim() || null;

      const lowestPrice = num(document.querySelector('.price.inline-with-icon.lowest-price-1')?.textContent);

      const priceBoxText = clean(document.querySelector('.price-box-full-width-xxs-column')?.textContent) || '';
      const rangeMatch = priceBoxText.match(/([\d,]+)\s*-\s*([\d,]+)/);
      const priceRange = rangeMatch ? { min: num(rangeMatch[1]), max: num(rangeMatch[2]) } : null;
      const updatedMatch = priceBoxText.match(/Price Updated:\s*(.+?)(?:Price Range|$)/i);
      const priceUpdated = updatedMatch ? clean(updatedMatch[1]) : null;

      const marketGridText = clean(document.querySelector('.market-grid.platform-pc-only')?.textContent) || '';
      const avgBinMatch = marketGridText.match(/Average BIN\s*([\d,]+)/i);
      const cheapestMatch = marketGridText.match(/Cheapest Sale[^\d]*([\d,]+)/i);
      const eaAvgMatch = marketGridText.match(/EA Avg\. Price\s*([\d,]+)/i);

      // Trend text lives near the top of the price panel, format: "29.69% (+19K)"
      const bodyText = document.body.innerText;
      const trendMatch = bodyText.match(/Trend:\s*([\-\d.]+%\s*\([^)]+\))/i);

      return {
        lowestPrice,
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
      futbinId,
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
