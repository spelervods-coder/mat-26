/**
 * FC26 SCRAPER TOOLKIT - SETUP SCRIPT
 * 
 * Dit script creëert de volledige folder-structuur en template-bestanden
 * voor de 4-bronnen scraper (FUTBIN, FUT.GG, FUTWIZ, FutNext)
 * 
 * Gebruik: node scraper-setup.js
 */

const fs = require('fs');
const path = require('path');

const BASE_DIR = './scraper-toolkit';

// Template files
const templates = {
  'package.json': `{
  "name": "fc26-scraper-toolkit",
  "version": "1.0.0",
  "description": "FC26 market data scraper - FUTBIN, FUT.GG, FUTWIZ, FutNext",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "node index.js Mbappe",
    "scrape:all": "node index.js",
    "scrape:futbin": "node futbin-scraper.js",
    "scrape:futgg": "node futgg-scraper.js",
    "scrape:futwiz": "node futwiz-scraper.js",
    "scrape:futnext": "node futnext-scraper.js"
  },
  "keywords": ["fc26", "fut", "scraper", "market"],
  "author": "spelervods-coder",
  "license": "MIT",
  "dependencies": {
    "puppeteer": "^22.0.0",
    "puppeteer-extra": "^3.3.6",
    "puppeteer-extra-plugin-stealth": "^2.11.2",
    "axios": "^1.6.0",
    "cheerio": "^1.0.0-rc.12",
    "dotenv": "^16.3.1"
  }
}`,

  '.env.example': `# FUTBIN Settings
FUTBIN_URL=https://www.futbin.com

# FUT.GG Settings
FUTGG_URL=https://www.fut.gg

# FUTWIZ Settings
FUTWIZ_URL=https://www.futwiz.com

# FutNext Settings
FUTNEXT_URL=https://www.futnext.com

# Scraper Settings
HEADLESS=true
DELAY_MS=1000
BATCH_SIZE=50
OUTPUT_DIR=./output

# User-Agent Rotation
USER_AGENTS=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36,Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36`,

  'README.md': `# FC26 Scraper Toolkit

**4-Source Market Data Scraper** for EA FC26 Ultimate Team

## Sources
- FUTBIN.com (prices, trends)
- FUT.GG (ratings, meta)
- FUTWIZ.com (market values)
- FutNext.com (pack odds)

## Setup

\`\`\`bash
npm install
cp .env.example .env
node index.js "Mbappe"
\`\`\`

## Commands

\`\`\`bash
npm start                 # Scrape all sources
npm run scrape:futbin     # FUTBIN only
npm run scrape:futgg      # FUT.GG only
npm run scrape:futwiz     # FUTWIZ only
npm run scrape:futnext    # FutNext only
\`\`\`

## Output

Result: \`cards.json\` (merged data from all 4 sources)

\`\`\`json
{
  "players": [
    {
      "playerName": "Mbappe",
      "cardId": "123456",
      "futbin": { "price": 72000, "trend": "+5.11%" },
      "futgg": { "rating": 91, "updated": "2024-08-14T14:30Z" },
      "futwiz": { "marketValue": 72500, "range": "70K-75K" },
      "futnext": { "packOdds": 0.0012 }
    }
  ]
}
\`\`\`

## Risks

⚠️ Web scraping may violate ToS. Use responsibly.
- Stealth plugin enabled
- Request delays (1s default)
- Rotate User-Agents
- Scrape off-peak hours

## License

MIT`,

  'index.js': `/**
 * FC26 SCRAPER ORCHESTRATOR
 * 
 * Coordinates scraping from all 4 sources in parallel
 * Merges results into unified cards.json
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');

const futbinScraper = require('./futbin-scraper');
const futggScraper = require('./futgg-scraper');
const futwizScraper = require('./futwiz-scraper');
const futnextScraper = require('./futnext-scraper');
const { mergePrices } = require('./mergePrices');

const OUTPUT_DIR = process.env.OUTPUT_DIR || './output';

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

async function scrapePlayer(playerName) {
  console.log(\`\\n🔍 Scraping all sources for: \${playerName}\`);
  
  try {
    // Scrape all sources in parallel
    const [futbinData, futggData, futwizData, futnextData] = await Promise.all([
      futbinScraper.scrape(playerName).catch(e => {
        console.error(\`❌ FUTBIN failed:\`, e.message);
        return null;
      }),
      futggScraper.scrape(playerName).catch(e => {
        console.error(\`❌ FUT.GG failed:\`, e.message);
        return null;
      }),
      futwizScraper.scrape(playerName).catch(e => {
        console.error(\`❌ FUTWIZ failed:\`, e.message);
        return null;
      }),
      futnextScraper.scrape(playerName).catch(e => {
        console.error(\`❌ FutNext failed:\`, e.message);
        return null;
      }),
    ]);

    // Merge results
    const merged = mergePrices({
      playerName,
      futbinData,
      futggData,
      futwizData,
      futnextData,
    });

    console.log(\`✅ Merged data:\`, JSON.stringify(merged, null, 2));
    return merged;

  } catch (error) {
    console.error(\`❌ Scraping failed:\`, error);
    return null;
  }
}

async function scrapeMultiple(playerNames) {
  const results = [];
  
  for (const name of playerNames) {
    const data = await scrapePlayer(name);
    if (data) results.push(data);
    
    // Delay between requests
    await new Promise(r => setTimeout(r, process.env.DELAY_MS || 1000));
  }

  // Save to cards.json
  const outputPath = path.join(OUTPUT_DIR, 'cards.json');
  fs.writeFileSync(outputPath, JSON.stringify({ players: results }, null, 2));
  console.log(\`\\n📁 Saved to: \${outputPath}\`);
  
  return results;
}

// Main
(async () => {
  const playerNames = process.argv.slice(2);
  
  if (playerNames.length === 0) {
    console.log('Usage: node index.js "Player Name" "Another Player"');
    console.log('Example: node index.js Mbappe Ronaldo');
    process.exit(0);
  }

  await scrapeMultiple(playerNames);
  process.exit(0);
})();

module.exports = { scrapePlayer, scrapeMultiple };`,

  'futbin-scraper.js': `/**
 * FUTBIN SCRAPER
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const cheerio = require('cheerio');

puppeteer.use(StealthPlugin());

const FUTBIN_BASE = 'https://www.futbin.com/24';

async function scrape(playerName) {
  console.log(\`  📊 FUTBIN: Scraping "\${playerName}"...\`);
  
  let browser;
  try {
    browser = await puppeteer.launch({
      headless: process.env.HEADLESS !== 'false',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-blink-features=AutomationControlled',
      ],
    });

    const page = await browser.newPage();
    
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    );

    const searchUrl = \`\${FUTBIN_BASE}/player/search\`;
    await page.goto(searchUrl, { waitUntil: 'networkidle2', timeout: 10000 });

    await page.type('input[placeholder="Search..."]', playerName);
    await page.keyboard.press('Enter');
    await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 10000 });

    const content = await page.content();
    const \$ = cheerio.load(content);

    const priceElement = \$('.price-section .price').text().trim();
    const trendElement = \$('.price-section .trend').text().trim();
    const priceRange = \$('.price-range').text().trim();

    const result = {
      source: 'FUTBIN',
      price: parseFloat(priceElement.replace(/[^0-9.]/g, '')) || null,
      trend: trendElement || null,
      range: priceRange || null,
      url: page.url(),
      timestamp: new Date().toISOString(),
    };

    console.log(\`    ✅ FUTBIN:\`, result);
    return result;

  } catch (error) {
    console.error(\`    ❌ FUTBIN Error:\`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };`,

  'futgg-scraper.js': `/**
 * FUT.GG SCRAPER
 */

const axios = require('axios');

const FUTGG_API = 'https://www.fut.gg/api/players';

async function scrape(playerName) {
  console.log(\`  📊 FUT.GG: Scraping "\${playerName}"...\`);
  
  try {
    const response = await axios.get(FUTGG_API, {
      params: {
        search: playerName,
        limit: 1,
      },
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      timeout: 10000,
    });

    if (!response.data || !response.data.length) {
      throw new Error('No results found');
    }

    const player = response.data[0];

    const result = {
      source: 'FUT.GG',
      name: player.name || null,
      rating: player.rating || null,
      position: player.position || null,
      club: player.club || null,
      nation: player.nation || null,
      updated: new Date().toISOString(),
    };

    console.log(\`    ✅ FUT.GG:\`, result);
    return result;

  } catch (error) {
    console.error(\`    ❌ FUT.GG Error:\`, error.message);
    throw error;
  }
}

module.exports = { scrape };`,

  'futwiz-scraper.js': `/**
 * FUTWIZ SCRAPER
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const cheerio = require('cheerio');

puppeteer.use(StealthPlugin());

const FUTWIZ_BASE = 'https://www.futwiz.com';

async function scrape(playerName) {
  console.log(\`  📊 FUTWIZ: Scraping "\${playerName}"...\`);
  
  let browser;
  try {
    browser = await puppeteer.launch({
      headless: process.env.HEADLESS !== 'false',
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    });

    const page = await browser.newPage();
    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
    );

    const searchUrl = \`\${FUTWIZ_BASE}/search?q=\${encodeURIComponent(playerName)}\`;
    await page.goto(searchUrl, { waitUntil: 'networkidle2', timeout: 10000 });

    const content = await page.content();
    const \$ = cheerio.load(content);

    const marketValue = \$('.market-value').text().trim();
    const range = \$('.price-range').text().trim();
    const demand = \$('.demand-level').text().trim();

    const result = {
      source: 'FUTWIZ',
      marketValue: parseFloat(marketValue.replace(/[^0-9.]/g, '')) || null,
      range: range || null,
      demand: demand || null,
      timestamp: new Date().toISOString(),
    };

    console.log(\`    ✅ FUTWIZ:\`, result);
    return result;

  } catch (error) {
    console.error(\`    ❌ FUTWIZ Error:\`, error.message);
    throw error;
  } finally {
    if (browser) await browser.close();
  }
}

module.exports = { scrape };`,

  'futnext-scraper.js': `/**
 * FUTNEXT SCRAPER
 */

const axios = require('axios');

const FUTNEXT_API = 'https://api.futnext.com/players';

async function scrape(playerName) {
  console.log(\`  📊 FutNext: Scraping "\${playerName}"...\`);
  
  try {
    const response = await axios.get(FUTNEXT_API, {
      params: {
        q: playerName,
      },
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      timeout: 10000,
    });

    if (!response.data || !response.data.length) {
      throw new Error('No results found');
    }

    const player = response.data[0];

    const result = {
      source: 'FutNext',
      packOdds: player.packOdds || null,
      nextRelease: player.nextRelease || null,
      availability: player.availability || null,
      updated: new Date().toISOString(),
    };

    console.log(\`    ✅ FutNext:\`, result);
    return result;

  } catch (error) {
    console.error(\`    ❌ FutNext Error:\`, error.message);
    throw error;
  }
}

module.exports = { scrape };`,

  'mergePrices.js': `/**
 * MERGE PRICES from all 4 sources
 */

function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData }) {
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
      averagePrice: calculateAverage([
        futbinData?.price,
        futwizData?.marketValue,
      ]),
      rating: futggData?.rating || null,
      position: futggData?.position || null,
      club: futggData?.club || null,
      nation: futggData?.nation || null,
      packOdds: futnextData?.packOdds || null,
      lastUpdated: new Date().toISOString(),
    },
  };
}

function calculateAverage(prices) {
  const valid = prices.filter(p => p !== null && p !== undefined);
  if (valid.length === 0) return null;
  return Math.round(valid.reduce((a, b) => a + b) / valid.length);
}

module.exports = { mergePrices };`,

  '.gitignore': `# Dependencies
node_modules/
npm-debug.log

# Output
output/
cards.json

# Environment
.env
.env.local

# Browser
.chromium/
chrome-data/

# System
.DS_Store
Thumbs.db

# Logs
*.log`,
};

// Create function
function setupScraperToolkit() {
  console.log('🚀 Creating FC26 Scraper Toolkit...\n');

  // Create base directory
  if (!fs.existsSync(BASE_DIR)) {
    fs.mkdirSync(BASE_DIR, { recursive: true });
    console.log(`✅ Created directory: ${BASE_DIR}`);
  }

  // Create files
  Object.entries(templates).forEach(([filename, content]) => {
    const filePath = path.join(BASE_DIR, filename);
    fs.writeFileSync(filePath, content);
    console.log(`✅ Created: ${filename}`);
  });

  // Create output directory
  const outputDir = path.join(BASE_DIR, 'output');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
    console.log(`✅ Created: output/`);
  }

  console.log('\n✨ Setup complete!\n');
  console.log('Next steps:');
  console.log(`  1. cd ${BASE_DIR}`);
  console.log('  2. npm install');
  console.log('  3. cp .env.example .env');
  console.log('  4. node index.js "Mbappe"');
}

setupScraperToolkit();
