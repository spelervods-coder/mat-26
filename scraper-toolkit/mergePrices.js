/**
 * MERGE DATA from all 4 sources into one composite card object.
 *
 * Approach (simple, will be refined later per user's note):
 * - Per-field FALLBACK CHAIN: for fields only some sources provide
 *   (rating, club, trend, playerId), take the first non-null value from
 *   a priority-ordered list of sources.
 * - BIN prices: keep ALL 4 raw values (binPrices), plus:
 *   - averageBinPrice: mean of whatever sources responded
 *   - lowestAcrossSources: {source, price} of the single cheapest BIN
 *     found anywhere - useful for "where to buy cheapest right now"
 * - No cross-source validation/discrepancy-flagging yet (e.g. warning
 *   when two sources disagree wildly) - noted as a future improvement.
 */

function firstNonNull(...vals) {
  for (const v of vals) {
    if (v !== null && v !== undefined) return v;
  }
  return null;
}

function formatMomentum(m) {
  if (!m) return null;
  return `avg ${m.average} (range ${m.lowest}-${m.highest})`;
}

function calculateAverage(prices) {
  const valid = prices.filter(p => typeof p === 'number' && !isNaN(p));
  if (valid.length === 0) return null;
  return Math.round(valid.reduce((a, b) => a + b, 0) / valid.length);
}

function mergePrices({ playerName, futbinData, futggData, futwizData, futnextData }) {
  const binPrices = {
    futbin: futbinData?.lowestPrice ?? null,
    futgg: futggData?.lowestBin ?? null,
    futwiz: futwizData?.marketValue ?? null,
    futnext: futnextData?.currentCheapest ?? null,
  };

  const validBins = Object.entries(binPrices).filter(([, v]) => typeof v === 'number');
  let lowestAcrossSources = null;
  if (validBins.length) {
    const [source, price] = validBins.reduce((min, cur) => (cur[1] < min[1] ? cur : min));
    lowestAcrossSources = { source, price };
  }

  return {
    playerName,
    playerId: firstNonNull(futggData?.playerId, futnextData?.futnextId, futwizData?.playerId, futwizData?.cardId),
    sources: {
      futbin: futbinData || { error: 'Failed to scrape' },
      futgg: futggData || { error: 'Failed to scrape' },
      futwiz: futwizData || { error: 'Failed to scrape' },
      futnext: futnextData || { error: 'Failed to scrape' },
    },
    merged: {
      binPrices,
      lowestAcrossSources,
      averageBinPrice: calculateAverage(Object.values(binPrices)),
      futbinLowest5: futbinData?.lowestPrices ?? null,
      rating: firstNonNull(futggData?.rating),
      position: firstNonNull(futggData?.position),
      club: firstNonNull(futggData?.club),
      nation: firstNonNull(futggData?.nation),
      trend: firstNonNull(
        futbinData?.trend,
        futggData?.priceMomentum ? formatMomentum(futggData.priceMomentum) : null
      ),
      lastUpdated: new Date().toISOString(),
    },
  };
}

module.exports = { mergePrices };
