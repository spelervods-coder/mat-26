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
