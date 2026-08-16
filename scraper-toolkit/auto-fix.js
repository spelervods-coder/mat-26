const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
console.log('🚀 [MAT-26] Automatische installatie & reparatie gestart...\n');
// 1. package.json
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
    "dotenv": "^16.4.5"
  }
};
fs.writeFileSync('package.json', JSON.stringify(packageJson, null, 2));
console.log('✅ package.json aangemaakt');
// 2. futbin-scraper.js
const futbinCode = `const axios = require('axios');
const cheerio = require('cheerio');
async function scrape(playerName) {
  console.log('  📊 FUTBIN: Scraping "' + playerName + '"...');
  try {
    const apiUrl = 'https://www.futbin.com/search?year=24&extra=1&v=1&term=' + encodeURIComponent(playerName);
    const response = await axios.get(apiUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': 'https://www.futbin.com/'
      },
      timeout: 8000
    });
    if (Array.isArray(response.data) && response.data.length > 0) {
      const player = response.data[0];
      const result = {
        source: 'FUTBIN',
        price: player.price || player.ps_price || player.xbox_price || null,
        rating: player.rating ? parseInt(player.rating, 10) : null,
        position: player.position || null,
        club: player.club_name || null,
        nation: player.nation_name || null,
        timestamp: new Date().toISOString()
      };
      console.log('    ✅ FUTBIN:', result);
      return result;
    }
    const htmlUrl = 'https://www.futbin.com/players?page=1&search=' + encodeURIComponent(playerName);
    const htmlRes = await axios.get(htmlUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
      timeout: 8000
    });
    const $ = cheerio.load(htmlRes.data);
    const price = $('span.price_amount, td.price, .price-badge').first().text().trim();
    const rating = $('span.rating').first().text().trim();
    const result = {
      source: 'FUTBIN',
      price: price || null,
      rating: rating ? parseInt(rating, 10) : null,
      timestamp: new Date().toISOString()
    };
    console.log('    ✅ FUTBIN:', result);
    return result;
  } catch (error) {
    console.error('    ❌ FUTBIN Error:', error.message);
    return { source: 'FUTBIN', price: null, error: error.message };
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futbin-scraper.js', futbinCode);
console.log('✅ futbin-scraper.js gefixt');
// 3. futgg-scraper.js
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
    const card = $('.player-card, [class*="player-card"]').first();
    let priceText = card.find('.player-card__price, [data-player-price], span.coins, .text-xs').first().text().trim() || $('.coins, .price').first().text().trim();
    const ratingText = card.find('.player-card__rating, [class*="rating"]').first().text().trim();
    const position = card.find('.player-card__position, [class*="position"]').first().text().trim() || null;
    const club = card.find('.player-card__club, [class*="club"]').first().text().trim() || null;
    const nation = card.find('.player-card__nation, [class*="nation"]').first().text().trim() || null;
    if (priceText) {
      const match = priceText.match(/(\\d+[\\d,.]*[kKmM]?)/);
      priceText = match ? match[1] : priceText;
    }
    const result = {
      source: 'FUT.GG',
      name: playerName,
      price: priceText || null,
      rating: ratingText ? parseInt(ratingText, 10) : null,
      position: position,
      club: club,
      nation: nation,
      updated: new Date().toISOString()
    };
    console.log('    ✅ FUT.GG:', result);
    return result;
  } catch (error) {
    console.error('    ❌ FUT.GG Error:', error.message);
    return { source: 'FUT.GG', price: null, error: error.message };
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futgg-scraper.js', futggCode);
console.log('✅ futgg-scraper.js gefixt');
// 4. futwiz-scraper.js
const futwizCode = `const axios = require('axios');
const cheerio = require('cheerio');
async function scrape(playerName) {
  console.log('  📊 FUTWIZ: Scraping "' + playerName + '"...');
  try {
    const searchUrl = 'https://www.futwiz.com/en/search?type=player&query=' + encodeURIComponent(playerName);
    const response = await axios.get(searchUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Referer': 'https://www.futwiz.com/'
      },
      timeout: 10000
    });
    const $ = cheerio.load(response.data);
    const priceText = $('.price-box, .bin-price, span.price, .card-24-pack-price, .latest-price').first().text().trim();
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
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futwiz-scraper.js', futwizCode);
console.log('✅ futwiz-scraper.js gefixt');
// 5. futnext-scraper.js
const futnextCode = `const axios = require('axios');
const cheerio = require('cheerio');
async function scrape(playerName) {
  console.log('  📊 FutNext: Scraping "' + playerName + '"...');
  try {
    const url = 'https://futnext.com/players?search=' + encodeURIComponent(playerName);
    const response = await axios.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://futnext.com/'
      },
      timeout: 8000
    });
    const $ = cheerio.load(response.data);
    const price = $('[class*="price"], .market-value, .coin-amount').first().text().trim() || null;
    const packOdds = $('.pack-odds, [class*="odds"]').first().text().trim() || null;
    const result = {
      source: 'FutNext',
      price: price,
      packOdds: packOdds,
      availability: 'Active',
      updated: new Date().toISOString()
    };
    console.log('    ✅ FutNext:', result);
    return result;
  } catch (error) {
    console.error('    ❌ FutNext Error:', error.message);
    return {
      source: 'FutNext',
      price: null,
      packOdds: null,
      availability: null,
      updated: new Date().toISOString()
    };
  }
}
module.exports = { scrape };
`;
fs.writeFileSync('futnext-scraper.js', futnextCode);
console.log('✅ futnext-scraper.js gefixt');
// 6. mergePrices.js
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
  const cleanNum = str.replace(/[^\\d]/g, '');
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
    futnextData?.price,
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
      rating: futbinData?.rating || futggData?.rating || futwizData?.rating || null,
      position: futggData?.position || futbinData?.position || null,
      club: futggData?.club || futbinData?.club || null,
      nation: futggData?.nation || futbinData?.nation || null,
      packOdds: futnextData?.packOdds || null,
      lastUpdated: new Date().toISOString(),
    },
  };
}
module.exports = { mergePrices, parsePrice, calculateAverage };
`;
fs.writeFileSync('mergePrices.js', mergePricesCode);
console.log('✅ mergePrices.js gefixt');
// 7. index.js
const indexCode = `require('dotenv').config();
const fs = require('fs');
const path = require('path');
const futbinScraper = require('./futbin-scraper');
const futggScraper = require('./futgg-scraper');
const futwizScraper = require('./futwiz-scraper');
const futnextScraper = require('./futnext-scraper');
const { mergePrices } = require('./mergePrices');
const OUTPUT_DIR = process.env.OUTPUT_DIR || './output';
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}
async function scrapePlayer(playerName) {
  console.log('\\n🔍 Scraping all sources for: ' + playerName);
  try {
    const [futbinData, futggData, futwizData, futnextData] = await Promise.all([
      futbinScraper.scrape(playerName).catch(e => {
        console.error('❌ FUTBIN failed:', e.message);
        return null;
      }),
      futggScraper.scrape(playerName).catch(e => {
        console.error('❌ FUT.GG failed:', e.message);
        return null;
      }),
      futwizScraper.scrape(playerName).catch(e => {
        console.error('❌ FUTWIZ failed:', e.message);
        return null;
      }),
      futnextScraper.scrape(playerName).catch(e => {
        console.error('❌ FutNext failed:', e.message);
        return null;
      }),
    ]);
    const merged = mergePrices({
      playerName,
      futbinData,
      futggData,
      futwizData,
      futnextData,
    });
    console.log('\\n✅ Merged data:', JSON.stringify(merged, null, 2));
    return merged;
  } catch (error) {
    console.error('❌ Scraping failed:', error);
    return null;
  }
}
async function scrapeMultiple(playerNames) {
  const results = [];
  for (const name of playerNames) {
    const data = await scrapePlayer(name);
    if (data) results.push(data);
    await new Promise(r => setTimeout(r, process.env.DELAY_MS || 1000));
  }
  const outputPath = path.join(OUTPUT_DIR, 'cards.json');
  fs.writeFileSync(outputPath, JSON.stringify({ players: results }, null, 2));
  console.log('\\n📁 Saved to: ' + outputPath + '\\n');
  return results;
}
(async () => {
  const playerNames = process.argv.slice(2).length > 0 ? process.argv.slice(2) : ['Mbappe'];
  await scrapeMultiple(playerNames);
  process.exit(0);
})();
module.exports = { scrapePlayer, scrapeMultiple };
`;
fs.writeFileSync('index.js', indexCode);
console.log('✅ index.js gefixt');
// 8. .env aanmaken
if (!fs.existsSync('.env')) {
  fs.writeFileSync('.env', 'OUTPUT_DIR=./output\nDELAY_MS=1000\n');
  console.log('✅ .env aangemaakt');
}
console.log('\n📦 Dependencies installeren (axios, cheerio, dotenv)...');
execSync('npm install axios cheerio dotenv --silent', { stdio: 'inherit' });
console.log('\n🎉 Setup voltooid! Nu live test draaien met Mbappe:\n');
execSync('node index.js Mbappe', { stdio: 'inherit' });
