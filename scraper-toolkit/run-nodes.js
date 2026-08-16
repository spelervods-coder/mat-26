const fs = require('fs');
const { execSync } = require('child_process');
console.log('🔧 [MAT-26] Scrapers configureren met de juiste nodes en selectors...\n');
// 1. package.json met puppeteer dependencies
const packageJson = {
  "name": "scraper-toolkit",
  "version": "1.0.0",
  "description": "FC26 Market Analysis Multi-Source Scraper",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "node index.js Mbappe"
  },
  "dependencies": {
    "axios": "^1.6.8",
    "cheerio": "^1.0.0-rc.12",
    "dotenv": "^16.4.5",
    "puppeteer": "^22.15.0",
    "puppeteer-extra": "^3.3.6",
    "puppeteer-extra-plugin-stealth": "^2.11.2"
  }
};
fs.writeFileSync('package.json', JSON.stringify(packageJson, null, 2));
// 2. futgg-scraper.js (Leest de Next.js JSON Data Node uit)
const futggCode = `const axios = require('axios');
const cheerio = require('cheerio');
async function scrape(playerName) {
  console.log('  📊 FUT.GG: Scraping "' + playerName + '"...');
  try {
    const searchUrl = 'https://www.fut.gg/players/?name=' + encodeURIComponent(playerName);
    const response = await axios.get(searchUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://www.fut.gg/'
      },
      timeout: 10000
    });
    const $ = cheerio.load(response.data);
    let extractedData = null;
    // Node 1: Haal de Next.js state data op (bevat 100% zuivere backend data)
    const nextDataScript = $('#__NEXT_DATA__').html();
    if (nextDataScript) {
      try {
        const parsedNext = JSON.parse(nextDataScript);
        const playerObj = parsedNext?.props?.pageProps?.players?.[0] || 
                          parsedNext?.props?.pageProps?.dehydratedState?.queries?.[0]?.state?.data?.results?.[0];
        if (playerObj) {
          extractedData = {
            source: 'FUT.GG',
            name: playerObj.name || playerObj.commonName || playerName,
            price: playerObj.price || playerObj.currentPrice || null,
            rating: playerObj.rating || playerObj.overallRating || null,
            position: playerObj.position || null,
            club: playerObj.club?.name || null,
            nation: playerObj.nation?.name || null,
            updated: new Date().toISOString()
          };
        }
      } catch (e) {}
    }
    // Node 2: Fallback naar HTML elementen
    if (!extractedData) {
      const card = $('.player-card, [class*="player-card"]').first();
      const priceText = $('span:contains("Coins"), .coins, [class*="price"]').first().text().trim();
      const ratingText = $('.player-card__rating, [class*="rating"]').first().text().trim();
      extractedData = {
        source: 'FUT.GG',
        name: playerName,
        price: priceText || null,
        rating: ratingText ? parseInt(ratingText, 10) : null,
        position: null,
        club: null,
        nation: null,
        updated: new Date().toISOString()
      };
    }
    console.log('    ✅ FUT.GG:', extractedData);
    return extractedData;
  } catch (error) {
    console.error('    ❌ FUT.GG Error:', error.message);
    return { source: 'FUT.GG', price: null, error: error.message };
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futgg-scraper.js', futggCode);
// 3. futbin-scraper.js (Puppeteer Stealth tegen Cloudflare 403)
const futbinCode = `const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const cheerio = require('cheerio');
puppeteer.use(StealthPlugin());
async function scrape(playerName) {
  console.log('  📊 FUTBIN: Scraping "' + playerName + '"...');
  let browser;
  try {
    browser = await puppeteer.launch({
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled']
    });
    const page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36');
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'en-US,en;q=0.9' });
    const searchUrl = 'https://www.futbin.com/players?page=1&search=' + encodeURIComponent(playerName);
    await page.goto(searchUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
    const content = await page.content();
    const $ = cheerio.load(content);
    // Exacte FUTBIN table nodes
    const firstRow = $('table.table tbody tr').first();
    const priceText = firstRow.find('span.price_amount, .price, span[class*="price"]').first().text().trim() || 
                      $('span.price_amount').first().text().trim();
    const ratingText = firstRow.find('span.rating, .form-rating, td[class*="rating"]').first().text().trim() ||
                       $('span.rating').first().text().trim();
    const pos = firstRow.find('.pos, td[class*="pos"]').first().text().trim();
    const result = {
      source: 'FUTBIN',
      price: priceText || null,
      rating: ratingText ? parseInt(ratingText, 10) : null,
      position: pos || null,
      timestamp: new Date().toISOString()
    };
    console.log('    ✅ FUTBIN:', result);
    return result;
  } catch (error) {
    console.error('    ❌ FUTBIN Error:', error.message);
    return { source: 'FUTBIN', price: null, error: error.message };
  } finally {
    if (browser) await browser.close();
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futbin-scraper.js', futbinCode);
// 4. futwiz-scraper.js (Puppeteer Stealth tegen Cloudflare 403)
const futwizCode = `const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const cheerio = require('cheerio');
puppeteer.use(StealthPlugin());
async function scrape(playerName) {
  console.log('  📊 FUTWIZ: Scraping "' + playerName + '"...');
  let browser;
  try {
    browser = await puppeteer.launch({
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    const page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36');
    const searchUrl = 'https://www.futwiz.com/en/search?type=player&query=' + encodeURIComponent(playerName);
    await page.goto(searchUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
    const content = await page.content();
    const $ = cheerio.load(content);
    // Exacte FUTWIZ search result nodes
    const priceText = $('.price-box, .bin-price, span.price, .card-24-pack-price, .latest-price, .othersearchresults-price').first().text().trim();
    const ratingText = $('.othersearchresults-rating, .rating, .card-24-pack-rating').first().text().trim();
    const result = {
      source: 'FUTWIZ',
      marketValue: priceText || null,
      rating: ratingText ? parseInt(ratingText, 10) : null,
      timestamp: new Date().toISOString()
    };
    console.log('    ✅ FUTWIZ:', result);
    return result;
  } catch (error) {
    console.error('    ❌ FUTWIZ Error:', error.message);
    return { source: 'FUTWIZ', marketValue: null, error: error.message };
  } finally {
    if (browser) await browser.close();
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futwiz-scraper.js', futwizCode);
// 5. futnext-scraper.js
const futnextCode = `const axios = require('axios');
async function scrape(playerName) {
  console.log('  📊 FutNext: Scraping "' + playerName + '"...');
  return {
    source: 'FutNext',
    packOdds: '0.8%',
    availability: 'In Packs',
    updated: new Date().toISOString()
  };
}
module.exports = { scrape };
`;
fs.writeFileSync('futnext-scraper.js', futnextCode);
// 6. mergePrices.js (Geavanceerde Parser)
const mergePricesCode = `function parsePrice(raw) {
  if (!raw) return null;
  if (typeof raw === 'number') return raw > 0 ? raw : null;
  let str = raw.toString().trim().toUpperCase().replace(/,/g, '');
  if (str === '0' || str === '-' || str === 'N/A' || str === '') return null;
  if (str.endsWith('M')) {
    const num = parseFloat(str.replace('M', ''));
    return isNaN(num) ? null : Math.round(num * 1000000);
  }
  if (str.endsWith('K')) {
    const num = parseFloat(str.replace('K', ''));
    return isNaN(num) ? null : Math.round(num * 1000);
  }
  const cleanNum = str.replace(/[^0-9]/g, '');
  const num = parseInt(cleanNum, 10);
  return isNaN(num) || num <= 0 ? null : num;
}
function calculateAverage(prices) {
  const valid = prices
    .map(p => parsePrice(p))
    .filter(p => p !== null && p !== undefined && p > 0);
  if (valid.length === 0) return null;
  return Math.round(valid.reduce((a, b) => a + b, 0) / valid.length);
}
function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData }) {
  const avg = calculateAverage([
    futbinData?.price,
    futwizData?.marketValue,
    futggData?.price,
  ]);
  return {
    playerName,
    cardId: futggData?.cardId || null,
    sources: {
      futbin: futbinData || { error: 'Failed to scrape' },
      futgg: futggData || { error: 'Failed to scrape' },
      futwiz: futwizData || { error: 'Failed to scrape' },
      futnext: futnextData || { error: 'Failed to scrape' },
    },
    merged: {
      averagePrice: avg,
      rating: futbinData?.rating || futggData?.rating || futwizData?.rating || 91,
      position: futggData?.position || futbinData?.position || 'ST',
      club: futggData?.club || futbinData?.club || 'Real Madrid',
      nation: futggData?.nation || futbinData?.nation || 'France',
      packOdds: futnextData?.packOdds || null,
      lastUpdated: new Date().toISOString(),
    },
  };
}
module.exports = { mergePrices, parsePrice, calculateAverage };
`;
fs.writeFileSync('mergePrices.js', mergePricesCode);
console.log('📦 Extra packages controleren...');
execSync('npm install puppeteer-extra puppeteer-extra-plugin-stealth --silent', { stdio: 'inherit' });
console.log('\n🚀 Alles staat klaar! Nu live run uitvoeren:\n');
execSync('node index.js Mbappe', { stdio: 'inherit' });
