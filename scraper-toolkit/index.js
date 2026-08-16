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
