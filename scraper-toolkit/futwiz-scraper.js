/**
 * FUTWIZ SCRAPER
 *
 * BIN price and Card ID confirmed via DevTools element picker.
 * Using text-pattern matching for Card ID (more stable than the raw
 * Tailwind class chain, which is not a unique/semantic identifier).
 * BIN price color class (text-cyan-300) is a design-system token and
 * reasonably stable, used with an attribute-contains selector as fallback-safe.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, futwizId, slug) {
  console.log(`  📊 FUTWIZ: Scraping "${playerName}" (id=${futwizId})...`);

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

    const url = `https://www.futwiz.com/fc26/player/${slug}/${futwizId}`;
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
      const addedMatch = bodyText.match(/Added\s*\n?\s*([A-Za-z]+ \d{1,2},?\s*\d{4}[^\\n]*)/i);
      const likesMatch = bodyText.match(/(\d+)%?\s*Like/i);

      return {
        marketValue,
        cardId: cardIdMatch ? cardIdMatch[1] : null,
        playerId: playerIdMatch ? playerIdMatch[1] : null,
        added: addedMatch ? addedMatch[1].trim() : null,
        likesPercent: likesMatch ? parseInt(likesMatch[1], 10) : null,
      };
    });

    const result = {
      source: 'FUTWIZ',
      futwizId,
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
