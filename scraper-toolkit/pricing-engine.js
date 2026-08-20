/**
 * PRICING ENGINE (v1, shadow-mode-ready)
 *
 * Implements the Hybrid TOS scoring approach from PRICING_STRATEGY.md,
 * adapted to the fields our scrapers actually produce. TOS weights
 * (35/30/20/15) are v1 arbitrary starting values - recalibrate via
 * logistic regression once 20-30 closed positions exist (report §5.2,
 * Fase C) - NEVER auto-adjusted silently, always in overleg.
 */

const EA_TAX = 0.05;

// --- Slot capacity pressure (report §6.2) ---
// 0-40: no pressure. 40-90: linear ramp. 90-97: steep. 97-100: blocked.
// Midpoint ~82 so pressure is already strong by 95-97 (per feedback:
// "heel moeilijk om boven de 95-97 te komen").
function slotPressureMultiplier(activeSlots) {
  if (activeSlots <= 40) return 1.0;
  if (activeSlots >= 97) return 0.0; // no new buy recommendations at all
  if (activeSlots <= 90) {
    const t = (activeSlots - 40) / (90 - 40);
    return 1.0 - t * 0.6; // 1.0 -> 0.4
  }
  const t = (activeSlots - 90) / (97 - 90);
  return 0.4 - t * 0.35; // 0.4 -> 0.05
}

// --- Max cards of the same cardId (report §6) ---
// hardCap default 4 (proposed: less concentration risk than 5, more
// upside room than 3 - adjustable in overleg once we see real outcomes).
function maxCardsForPlayer(accountBudget, buyPrice, { maxPct = 0.125, hardCap = 4 } = {}) {
  const pctCap = buyPrice > 0 ? Math.floor((accountBudget * maxPct) / buyPrice) : 0;
  return Math.max(0, Math.min(pctCap, hardCap));
}

// --- FC26 price ticks ---
function roundToTick(price) {
  const tick = price < 50000 ? 250 : 500;
  return Math.round(price / tick) * tick;
}

// --- TOS sub-scores (0-10 each) ---
function profitPotentialScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  return Math.max(0, Math.min(10, 10 - pct / 10)); // lower in range = more upside
}

function liquidityScore(merged) {
  const ratio = merged.marketLiquidityRatio;
  if (ratio === null || ratio === undefined) return 5; // unknown -> neutral, don't fake confidence
  return Math.max(0, Math.min(10, ratio * 5)); // ratio ~1.0 balanced -> score 5
}

function meanReversionScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  if (pct <= 50) return Math.min(10, 5 + (50 - pct) / 5);
  return Math.max(0, 5 - (pct - 50) / 10);
}

function rangePositionScore(merged) {
  const pct = merged.binPricePercentInRange;
  if (pct === null || pct === undefined) return 5;
  return Math.max(0, Math.min(10, 10 - pct / 10));
}

const TOS_WEIGHTS = { profit: 0.35, liquidity: 0.30, meanReversion: 0.20, range: 0.15 };

function calculateTOS(merged) {
  const profit = profitPotentialScore(merged);
  const liquidity = liquidityScore(merged);
  const meanReversion = meanReversionScore(merged);
  const range = rangePositionScore(merged);

  const tos = profit * TOS_WEIGHTS.profit
    + liquidity * TOS_WEIGHTS.liquidity
    + meanReversion * TOS_WEIGHTS.meanReversion
    + range * TOS_WEIGHTS.range;

  return {
    tos: Math.round(tos * 10) / 10,
    subScores: { profit, liquidity, meanReversion, range },
    weights: { ...TOS_WEIGHTS },
  };
}

// --- Buy/sell price recommendation ---
const RISK_PROFILES = {
  conservative: { minMarginPct: 0.10 },
  standard: { minMarginPct: 0.06 },
  aggressive: { minMarginPct: 0.03 },
};

function recommendPrices(merged, {
  riskProfile = 'standard',
  activeSlots = 0,
  inventoryQ = 0,
} = {}) {
  const profile = RISK_PROFILES[riskProfile] || RISK_PROFILES.standard;
  const bin = merged.lowestAcrossSources?.price ?? merged.averageBinPrice;
  if (!bin) return null;

  const pressure = slotPressureMultiplier(activeSlots);
  // Slot pressure LOWERS the margin requirement (prioritize turnover
  // when the transfer list is nearly full) - report §2.3/§6.2.
  const marginPct = Math.max(0.02, profile.minMarginPct * (0.4 + 0.6 * pressure));

  // Inventory penalty (Avellaneda-Stoikov style soft dampening) - more
  // of this card already held -> aim for a slightly lower sell price to
  // move it faster.
  const inventoryPenalty = Math.max(0.5, 1 - 0.03 * inventoryQ);

  const sellPrice = roundToTick(bin * inventoryPenalty);
  const netRevenue = sellPrice * (1 - EA_TAX);
  const buyPrice = roundToTick(netRevenue / (1 + marginPct));

  const expectedProfit = Math.round(netRevenue - buyPrice);
  const expectedRoiPct = buyPrice > 0 ? Math.round((expectedProfit / buyPrice) * 1000) / 10 : 0;

  return {
    buyPrice,
    sellPrice,
    expectedProfit,
    expectedRoiPct,
    marginPctUsed: Math.round(marginPct * 1000) / 10,
    slotPressure: Math.round(pressure * 100) / 100,
  };
}

// --- Relist price: RE-RUNS the engine with FRESH data (not a fixed
// decrement of the old price - market may have moved either direction
// since the original listing, per feedback). A single-step cap prevents
// overreacting to one noisy scrape.
function recommendRelistPrice(merged, previousListPrice, opts = {}) {
  const fresh = recommendPrices(merged, opts);
  if (!fresh) return null;

  const maxStepPct = 0.15; // never move more than 15% in one relist step
  const floor = previousListPrice * (1 - maxStepPct);
  const ceiling = previousListPrice * (1 + maxStepPct);
  const cappedSellPrice = roundToTick(Math.max(floor, Math.min(fresh.sellPrice, ceiling)));

  return { ...fresh, sellPrice: cappedSellPrice, previousListPrice, wasCapped: cappedSellPrice !== fresh.sellPrice };
}

module.exports = {
  EA_TAX,
  slotPressureMultiplier,
  maxCardsForPlayer,
  roundToTick,
  calculateTOS,
  recommendPrices,
  recommendRelistPrice,
  RISK_PROFILES,
};
