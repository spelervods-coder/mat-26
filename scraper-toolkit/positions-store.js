/**
 * POSITION TRACKING (report §6.1, §7.1)
 *
 * One positionId per BOUGHT card instance - NOT per cardId. A cardId
 * (e.g. Mbappé Gold Rare) can have several open positions at once if
 * you bought multiple copies at different times/prices.
 *
 * Stored as a single JSON object keyed by positionId (like players-db.json)
 * rather than JSONL, because positions get UPDATED over their lifecycle
 * (buy -> list -> expire -> relist -> sold), not just appended once.
 *
 * IMPORTANT (corrected per user feedback): EA does NOT automatically
 * return an expired listing to your club - it stays on the transfer
 * list until you manually collect it. So "expired" positions still
 * count toward your 100-slot limit until you take further action.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const POSITIONS_FILE = path.join(process.env.OUTPUT_DIR || './output', 'positions.json');

function loadPositions() {
  if (!fs.existsSync(POSITIONS_FILE)) return {};
  try {
    return JSON.parse(fs.readFileSync(POSITIONS_FILE, 'utf8'));
  } catch (e) {
    console.error('⚠️  Could not parse positions.json:', e.message);
    return {};
  }
}

function savePositions(positions) {
  const dir = path.dirname(POSITIONS_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(POSITIONS_FILE, JSON.stringify(positions, null, 2));
}

function createPosition(cardId, playerName, buyPrice) {
  const positions = loadPositions();
  const positionId = crypto.randomUUID();
  positions[positionId] = {
    positionId,
    cardId,
    playerName,
    events: [{ action: 'buy', price: buyPrice, timestamp: new Date().toISOString() }],
    holdUntil: null,
    relistCount: 0,
    status: 'open', // open | closed | stuck
    finalProfit: null,
  };
  savePositions(positions);
  return positions[positionId];
}

function addEvent(positionId, event) {
  const positions = loadPositions();
  const pos = positions[positionId];
  if (!pos) return null;

  pos.events.push({ ...event, timestamp: new Date().toISOString() });

  if (event.action === 'relist') pos.relistCount = (pos.relistCount || 0) + 1;

  if (event.action === 'sold') {
    pos.status = 'closed';
    const buyEvent = pos.events.find(e => e.action === 'buy');
    const netPrice = event.netPrice ?? Math.round(event.price * 0.95);
    pos.finalProfit = netPrice - (buyEvent?.price ?? 0);
  }

  if (event.action === 'stuck') pos.status = 'stuck';

  savePositions(positions);
  return pos;
}

function getPosition(positionId) {
  return loadPositions()[positionId] || null;
}

function getAllPositions() {
  return Object.values(loadPositions());
}

function getOpenPositions() {
  // "open" here means "still occupying a transfer-list slot" - includes
  // bought-not-listed, listed-not-sold, AND expired-not-yet-relisted
  // (see IMPORTANT note above - EA doesn't auto-clear these).
  return getAllPositions().filter(p => p.status === 'open');
}

function countActiveSlots() {
  return getOpenPositions().length;
}

function countPositionsForCard(cardId) {
  return getOpenPositions().filter(p => String(p.cardId) === String(cardId)).length;
}

function findPositionByPrefix(idPrefix) {
  const positions = loadPositions();
  const match = Object.keys(positions).find(id => id.startsWith(idPrefix));
  return match ? positions[match] : null;
}

module.exports = {
  createPosition, addEvent, getPosition, getAllPositions, getOpenPositions,
  countActiveSlots, countPositionsForCard, findPositionByPrefix, POSITIONS_FILE,
};
