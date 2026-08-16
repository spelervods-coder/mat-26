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
