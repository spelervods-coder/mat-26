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
