# apply-fixes.ps1
# Writes all scraper fixes into place and sets up the git-checkpoint script.
# Run this from D:\Projects\mat-26\scraper-toolkit

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\index.js")) {
  Write-Host "ERROR: run this script from inside the scraper-toolkit folder (where index.js normally lives)." -ForegroundColor Red
  Write-Host "  cd D:\Projects\mat-26\scraper-toolkit" -ForegroundColor Yellow
  exit 1
}

Write-Host "Writing scraper files..." -ForegroundColor Cyan

$content_futbin_scraper_js = @'
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

'@
Set-Content -Path ".\futbin-scraper.js" -Value $content_futbin_scraper_js -NoNewline
Write-Host "  wrote futbin-scraper.js" -ForegroundColor Green

$content_futgg_scraper_js = @'
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

'@
Set-Content -Path ".\futgg-scraper.js" -Value $content_futgg_scraper_js -NoNewline
Write-Host "  wrote futgg-scraper.js" -ForegroundColor Green

$content_futwiz_scraper_js = @'
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

'@
Set-Content -Path ".\futwiz-scraper.js" -Value $content_futwiz_scraper_js -NoNewline
Write-Host "  wrote futwiz-scraper.js" -ForegroundColor Green

$content_futnext_scraper_js = @'
/**
 * FUTNEXT SCRAPER
 *
 * Using text-pattern matching for Current Cheapest / Lowest (24H) /
 * Average (24H) / 24h change - the raw Tailwind class chains shown in
 * DevTools are long utility combinations, not stable identifiers.
 */

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

async function scrape(playerName, futnextId, slug) {
  console.log(`  📊 FutNext: Scraping "${playerName}" (id=${futnextId})...`);

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

    // slug should be the player name, NOT pre-encoded - encodeURIComponent
    // handles accented characters (é etc.) correctly here
    const url = `https://www.futnext.com/player/${encodeURIComponent(slug)}/${futnextId}`;
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

      const cheapestMatch = bodyText.match(/^([\d,]+)\s*$/m); // top-of-page price display
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
      futnextId,
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

'@
Set-Content -Path ".\futnext-scraper.js" -Value $content_futnext_scraper_js -NoNewline
Write-Host "  wrote futnext-scraper.js" -ForegroundColor Green

$content_index_js = @'
/**
 * FC26 SCRAPER ORCHESTRATOR
 *
 * Reads player definitions (with per-site IDs) from players.json and
 * scrapes all 4 sources in parallel per player.
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
const PLAYERS_FILE = './players.json';
const DELAY_MS = parseInt(process.env.DELAY_MS || '1000', 10);

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

async function scrapePlayer(playerDef) {
  const { playerName, futbin, futgg, futwiz, futnext } = playerDef;
  console.log(`\n🔍 Scraping all sources for: ${playerName}`);

  const [futbinData, futggData, futwizData, futnextData] = await Promise.all([
    futbinScraper.scrape(playerName, futbin.id, futbin.slug).catch(e => {
      console.error(`❌ FUTBIN failed:`, e.message);
      return null;
    }),
    futggScraper.scrape(playerName, futgg.id, futgg.slug).catch(e => {
      console.error(`❌ FUT.GG failed:`, e.message);
      return null;
    }),
    futwizScraper.scrape(playerName, futwiz.id, futwiz.slug).catch(e => {
      console.error(`❌ FUTWIZ failed:`, e.message);
      return null;
    }),
    futnextScraper.scrape(playerName, futnext.id, futnext.slug).catch(e => {
      console.error(`❌ FutNext failed:`, e.message);
      return null;
    }),
  ]);

  const merged = mergePrices({ playerName, futbinData, futggData, futwizData, futnextData });
  console.log(`✅ Merged data:`, JSON.stringify(merged, null, 2));
  return merged;
}

async function scrapeAll() {
  if (!fs.existsSync(PLAYERS_FILE)) {
    console.log(`❌ ${PLAYERS_FILE} not found. Add players there first (see players.json.example).`);
    process.exit(1);
  }

  const { players } = JSON.parse(fs.readFileSync(PLAYERS_FILE, 'utf8'));
  const results = [];

  for (const playerDef of players) {
    const data = await scrapePlayer(playerDef);
    if (data) results.push(data);
    await new Promise(r => setTimeout(r, DELAY_MS));
  }

  const outputPath = path.join(OUTPUT_DIR, 'cards.json');
  fs.writeFileSync(outputPath, JSON.stringify({ players: results }, null, 2));
  console.log(`\n📁 Saved to: ${outputPath}`);

  return results;
}

(async () => {
  await scrapeAll();
  process.exit(0);
})();

module.exports = { scrapePlayer, scrapeAll };

'@
Set-Content -Path ".\index.js" -Value $content_index_js -NoNewline
Write-Host "  wrote index.js" -ForegroundColor Green

$content_mergePrices_js = @'
/**
 * MERGE DATA from all 4 sources into one card object.
 *
 * Phase 1 scope (per user decision): BIN price from all 4 sources +
 * static card info (name, rating, position, club, nation, trend where
 * available). Sales-history detail tables come later once BIN works reliably.
 */

function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData }) {
  return {
    playerName,
    playerId: futggData?.playerId || futnextData?.futnextId || null,
    sources: {
      futbin: futbinData || { error: 'Failed to scrape' },
      futgg: futggData || { error: 'Failed to scrape' },
      futwiz: futwizData || { error: 'Failed to scrape' },
      futnext: futnextData || { error: 'Failed to scrape' },
    },
    merged: {
      binPrices: {
        futbin: futbinData?.lowestPrice ?? null,
        futgg: futggData?.lowestBin ?? null,
        futwiz: futwizData?.marketValue ?? null,
        futnext: futnextData?.currentCheapest ?? null,
      },
      averageBinPrice: calculateAverage([
        futbinData?.lowestPrice,
        futggData?.lowestBin,
        futwizData?.marketValue,
        futnextData?.currentCheapest,
      ]),
      rating: futggData?.rating ?? null,
      position: futggData?.position ?? null,
      club: futggData?.club ?? null,
      nation: futggData?.nation ?? null,
      trend: futbinData?.trend ?? null,
      lastUpdated: new Date().toISOString(),
    },
  };
}

function calculateAverage(prices) {
  const valid = prices.filter(p => typeof p === 'number' && !isNaN(p));
  if (valid.length === 0) return null;
  return Math.round(valid.reduce((a, b) => a + b, 0) / valid.length);
}

module.exports = { mergePrices };

'@
Set-Content -Path ".\mergePrices.js" -Value $content_mergePrices_js -NoNewline
Write-Host "  wrote mergePrices.js" -ForegroundColor Green

$content_players_json = @'
{
  "players": [
    {
      "playerName": "Kylian Mbappé",
      "searchName": "Mbappe",
      "futbin": { "id": "40", "slug": "kylian-mbappe" },
      "futgg": { "id": "231747", "slug": "kylian-mbappe" },
      "futwiz": { "id": "33", "slug": "kylian-mbappe" },
      "futnext": { "id": "231747", "slug": "kylian-mbappé" }
    }
  ]
}

'@
Set-Content -Path ".\players.json" -Value $content_players_json -NoNewline
Write-Host "  wrote players.json" -ForegroundColor Green

New-Item -ItemType Directory -Path "..\scripts" -Force | Out-Null
$content_git_checkpoint = @'
param(
  [Parameter(Mandatory=$true)]
  [string]$Message
)

# Fix Windows "dubious ownership" issue (safe to run every time)
$repoPath = (Get-Location).Path
git config --global --add safe.directory $repoPath | Out-Null

git add -A
$staged = git diff --cached --stat

if ([string]::IsNullOrWhiteSpace($staged)) {
  Write-Host "Nothing to commit - working tree matches last commit." -ForegroundColor Yellow
  exit 0
}

Write-Host "`nStaged changes:" -ForegroundColor Cyan
Write-Host $staged

git commit -m $Message

if ($LASTEXITCODE -eq 0) {
  Write-Host "`nCommitted: $Message" -ForegroundColor Green
  git push origin main
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Pushed to GitHub." -ForegroundColor Green
  } else {
    Write-Host "Push failed - if this is your first push, try:" -ForegroundColor Red
    Write-Host "  git push -u origin main" -ForegroundColor Yellow
    Write-Host "If remote has unrelated commits (README etc), try:" -ForegroundColor Red
    Write-Host "  git pull origin main --allow-unrelated-histories" -ForegroundColor Yellow
  }
} else {
  Write-Host "Commit failed - check errors above." -ForegroundColor Red
}

'@
Set-Content -Path "..\scripts\git-checkpoint.ps1" -Value $content_git_checkpoint -NoNewline
Write-Host "  wrote ..\scripts\git-checkpoint.ps1" -ForegroundColor Green

Write-Host ""
Write-Host "Done. All files replaced." -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Check/set CHROME_PATH in .env (see chat instructions)"
Write-Host "  2. node index.js"
Write-Host "  3. cd .."
Write-Host "  4. .\scripts\git-checkpoint.ps1 -Message fix: real BIN-price selectors + players.json"