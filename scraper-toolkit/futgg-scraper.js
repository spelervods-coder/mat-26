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

      // DISABLED (v6): the naive "find heading text, grab next N lines"
      // approach was picking up unrelated content (PlayStyle labels etc,
      // not actual sales rows) - confirmed via a live test run. Rather
      // than return misleading data, this returns null until we have real
      // selectors (needs a DevTools element-pick screenshot of that
      // section once it has live data to inspect - same method used for
      // the BIN price selectors).

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
        recentSalesRaw: null, // disabled, see comment above
        liveAuctionsRaw: null, // disabled, see comment above
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
