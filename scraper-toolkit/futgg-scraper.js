/**
 * FUT.GG SCRAPER
 *
 * Static player attributes (rating, position, club, nation, player ID) ARE
 * present in server-rendered HTML - confirmed via direct fetch.
 * The BIN price is NOT in the static HTML ("PR" placeholder) - it hydrates
 * client-side, so Puppeteer is needed for price. We grab everything in one
 * pass to avoid a second request.
 *
 * "Lowest BIN" section appears BEFORE "Price Momentum" in DOM order, so the
 * first span.tabular-nums after the "Lowest BIN" heading is the price -
 * text-pattern matching is used instead of raw class chains since Tailwind
 * utility classes are not unique/stable identifiers.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, futggId, slug) {
  console.log(`  📊 FUT.GG: Scraping "${playerName}" (id=${futggId})...`);

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

    const url = `https://www.fut.gg/players/${futggId}-${slug}/26-${futggId}/`;
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

      // Lowest BIN = first tabular-nums span in DOM order (appears before
      // the Price Momentum section which has its own tabular-nums spans)
      const tabularSpans = Array.from(document.querySelectorAll('span.tabular-nums'));
      const lowestBin = tabularSpans.length ? num(tabularSpans[0].textContent) : null;

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
