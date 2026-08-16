/**
 * SIMPLE JSON-BACKED STORE for scraped player data.
 *
 * File: output/players-db.json - keyed by playerId (EA official ID).
 * Phase 1 storage (per project roadmap): JSON now, SQLite later once
 * this outgrows a flat file (e.g. >200 players or concurrent writes).
 */

const fs = require('fs');
const path = require('path');

const DB_FILE = path.join(process.env.OUTPUT_DIR || './output', 'players-db.json');

function loadDb() {
  if (!fs.existsSync(DB_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
  } catch (e) {
    console.error('⚠️  Could not parse players-db.json, starting fresh:', e.message);
    return {};
  }
}

function saveDb(db) {
  const dir = path.dirname(DB_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
}

function getEntry(playerId) {
  const db = loadDb();
  return db[playerId] || null;
}

function upsertEntry(playerId, mergedData) {
  const db = loadDb();
  db[playerId] = {
    ...mergedData,
    storedAt: new Date().toISOString(),
  };
  saveDb(db);
  return db[playerId];
}

function isStale(entry, maxAgeMinutes) {
  if (!entry || !entry.storedAt) return true;
  const ageMs = Date.now() - new Date(entry.storedAt).getTime();
  return ageMs > maxAgeMinutes * 60 * 1000;
}

module.exports = { loadDb, saveDb, getEntry, upsertEntry, isStale, DB_FILE };
