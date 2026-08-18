Here is a complete, interactive Python CLI script (called **`fc_pricing_runner.py`**) that implements everything discussed:

1. Asks for an **output directory path** and automatically writes modular Python and JavaScript engine files there.
2. Provides an interactive menu to choose which model you want to test:
   - **Model 1:** Avellaneda-Stoikov (Inventory & Volatility)
   - **Model 2:** Hazard Rate & Expected Value (Order Flow & Survival)
   - **Model 3:** Ornstein-Uhlenbeck (Mean Reversion & Trend)
   - **Model 4:** The Complete Hybrid 4-Layer Scoring Engine (TOS 0–10)
3. Prompts for every variable with **clear explanations, expected formats, and sensible default values** (press _Enter_ to keep defaults).
4. Computes the results live and displays a formatted trade breakdown (Prices, EA Tax, Net Profit, ROI %, Fill Rate, and Trade Decision).

---

### Python Script: `fc_pricing_runner.py`

Save this file and run it using: `python fc_pricing_runner.py`

```python
#!/usr/bin/env python3
"""
FC 26 Transfer Market Pricing & Opportunity CLI Suite
Supports Avellaneda-Stoikov, Hazard/EV, Ornstein-Uhlenbeck, and Hybrid TOS Engine.
"""

import os
import sys
import math
import json

# ==============================================================================
# 1. CORE QUANTITATIVE ALGORITHMS (Python Implementation)
# ==============================================================================

def get_fc_tick(price: float) -> int:
    """Standard FC 26 transfer market price tick increments."""
    if price < 1000:
        return 50
    elif price < 10000:
        return 100
    elif price < 50000:
        return 250
    elif price < 100000:
        return 500
    else:
        return 1000

def round_to_tick(price: float, round_down: bool = True) -> int:
    """Clamps a raw float price to valid FC transfer market ticks."""
    tick = get_fc_tick(price)
    if round_down:
        return int(math.floor(price / tick) * tick)
    return int(math.ceil(price / tick) * tick)

def calc_parkinson_volatility(min_24h: float, max_24h: float) -> float:
    """Estimates Parkinson continuous volatility from 24h high/low."""
    if max_24h > min_24h and min_24h > 0:
        return (math.log(max_24h) - math.log(min_24h)) / 1.665
    return 0.05

def run_avellaneda_stoikov(
    low_bin: float,
    min_24h: float,
    max_24h: float,
    sales_hr: float,
    listings_hr: float,
    inventory_q: int = 0,
    gamma: float = 0.1,
    time_to_event_hrs: float = 4.0,
    price_min_cap: float = 200,
    price_max_cap: float = 1000000
):
    sigma = calc_parkinson_volatility(min_24h, max_24h)
    fill_rate = sales_hr / max(listings_hr, 1.0)
    kappa = 1.0 / max(fill_rate, 0.05)
    time_factor = max(time_to_event_hrs, 0.2)

    # Reservation price penalized by inventory and event horizon
    r = low_bin - (inventory_q * gamma * (sigma ** 2) * (1.0 / time_factor) * low_bin)

    # Half spread
    spread_half = (1.0 / gamma) * math.log(1.0 + (gamma / kappa)) * (low_bin * 0.08)

    raw_sell = r + spread_half
    p_sell = round_to_tick(raw_sell / 0.95, round_down=False) # 5% EA tax adjusted
    p_sell = max(int(price_min_cap), min(p_sell, int(price_max_cap)))

    raw_buy = r - spread_half
    p_buy = round_to_tick(min(raw_buy, p_sell * 0.95 - 350), round_down=True)
    p_buy = max(int(price_min_cap), min(p_buy, int(price_max_cap)))

    net_profit = (p_sell * 0.95) - p_buy
    roi = (net_profit / p_buy * 100) if p_buy > 0 else 0

    return {
        "model": "Avellaneda-Stoikov (Inventory & Risk)",
        "sigma_volatility": round(sigma, 4),
        "reservation_price": int(r),
        "p_buy_max": p_buy,
        "p_sell_list": p_sell,
        "ea_tax": int(p_sell * 0.05),
        "net_profit": int(net_profit),
        "net_roi_pct": round(roi, 2)
    }

def run_hazard_rate_ev(
    low_bin: float,
    sales_hr: float,
    listings_hr: float,
    target_roi: float = 0.08,
    holding_hours: float = 1.0,
    price_min_cap: float = 200,
    price_max_cap: float = 1000000
):
    fill_rate = sales_hr / max(listings_hr, 1.0)
    p_fill = 1.0 - math.exp(-fill_rate * holding_hours)

    # Sell strategy: if high velocity list slightly above lowBIN, else match lowBIN
    if fill_rate > 0.85:
        target_sell = low_bin * 1.03
    else:
        target_sell = low_bin

    p_sell = round_to_tick(target_sell, round_down=False)
    p_sell = max(int(price_min_cap), min(p_sell, int(price_max_cap)))

    net_revenue = p_sell * 0.95
    # Max buy constrained by Target ROI and execution likelihood
    raw_buy = (net_revenue * p_fill) / (1.0 + target_roi)
    p_buy = round_to_tick(raw_buy, round_down=True)
    p_buy = max(int(price_min_cap), min(p_buy, int(price_max_cap)))

    net_profit = (p_sell * 0.95) - p_buy
    roi = (net_profit / p_buy * 100) if p_buy > 0 else 0

    return {
        "model": "Hazard Rate & Expected Value",
        "fill_rate_ratio": round(fill_rate, 3),
        "prob_sold_in_window": f"{round(p_fill * 100, 1)}%",
        "p_buy_max": p_buy,
        "p_sell_list": p_sell,
        "ea_tax": int(p_sell * 0.05),
        "net_profit": int(net_profit),
        "net_roi_pct": round(roi, 2)
    }

def run_ornstein_uhlenbeck(
    low_bin: float,
    avg_24h: float,
    min_24h: float,
    max_24h: float,
    trend_pct: float = 0.0,
    diff_pct: float = 0.0,
    price_min_cap: float = 200,
    price_max_cap: float = 1000000
):
    sigma_norm = max((max_24h - min_24h) / 4.0, 1.0)
    mu_target = avg_24h * (1.0 + 0.5 * (trend_pct / 100.0) + 0.2 * (diff_pct / 100.0))
    z_score = (low_bin - mu_target) / sigma_norm

    # Listing targets the mean reversion level
    p_sell = round_to_tick(max(mu_target, low_bin * 1.02), round_down=False)
    p_sell = max(int(price_min_cap), min(p_sell, int(price_max_cap)))

    # Buy target triggers in oversold conditions
    raw_buy = min(low_bin, mu_target - 0.5 * sigma_norm)
    # Hard EA tax margin filter
    raw_buy = min(raw_buy, (p_sell * 0.95) / 1.06)
    p_buy = round_to_tick(raw_buy, round_down=True)
    p_buy = max(int(price_min_cap), min(p_buy, int(price_max_cap)))

    net_profit = (p_sell * 0.95) - p_buy
    roi = (net_profit / p_buy * 100) if p_buy > 0 else 0

    return {
        "model": "Ornstein-Uhlenbeck Mean Reversion",
        "z_score": round(z_score, 2),
        "mean_reversion_target": int(mu_target),
        "p_buy_max": p_buy,
        "p_sell_list": p_sell,
        "ea_tax": int(p_sell * 0.05),
        "net_profit": int(net_profit),
        "net_roi_pct": round(roi, 2)
    }

def run_hybrid_tos(card_dict: dict, inventory_q: int = 0, account_budget: float = 1_000_000, hours_to_event: float = 4.0):
    low_bin = float(card_dict['lowBIN'])
    avg_24 = float(card_dict['avg24'])
    min_24 = float(card_dict['min24'])
    max_24 = float(card_dict['max24'])
    trend_pct = float(card_dict.get('trend_pct', 0.0))
    listings_hr = float(card_dict['listings_per_hour'])
    sales_hr = float(card_dict['sales_per_hour'])
    price_min_cap = float(card_dict['price_min_range'])
    price_max_cap = float(card_dict['price_max_range'])

    sigma = calc_parkinson_volatility(min_24, max_24)
    mu_target = avg_24 * (1.0 + (0.3 * (trend_pct / 100.0)))
    fill_rate = sales_hr / max(listings_hr, 1.0)
    p_sold_1h = 1.0 - math.exp(-fill_rate)
    kappa = 1.0 / max(fill_rate, 0.05)

    gamma = max(0.05, min(0.8, 100000 / max(account_budget, 10000)))
    time_factor = max(hours_to_event, 0.2)

    reservation_price = low_bin - (inventory_q * gamma * (sigma ** 2) * (1.0 / time_factor) * low_bin)
    spread_half = (1.0 / gamma) * math.log(1.0 + (gamma / kappa)) * low_bin * 0.1
    target_sell_raw = max(reservation_price + spread_half, mu_target * 0.98)

    p_sell = round_to_tick(target_sell_raw / 0.95, round_down=False)
    p_sell = min(p_sell, int(price_max_cap))

    net_sell_revenue = p_sell * 0.95
    min_abs_profit = 350.0 if low_bin < 10000 else 600.0
    target_roi = 0.05

    target_buy_raw = (net_sell_revenue - min_abs_profit) / (1.0 + target_roi)
    p_buy = round_to_tick(target_buy_raw, round_down=True)
    p_buy = max(p_buy, int(price_min_cap))

    net_profit = (p_sell * 0.95) - p_buy
    net_roi = (net_profit / p_buy) if p_buy > 0 else 0

    s_winst = max(0.0, min(10.0, ((net_roi - 0.04) / 0.10) * 10.0))
    s_liq = max(0.0, min(10.0, (0.6 * p_sold_1h + 0.4 * min(sales_hr / 40.0, 1.0)) * 10.0))
    z_score = (low_bin - avg_24) / max((max_24 - min_24) / 4.0, 1.0)
    s_rev = max(0.0, min(10.0, 5.0 - (2.5 * z_score) + (0.2 * trend_pct)))
    range_pos = (low_bin - price_min_cap) / max(price_max_cap - price_min_cap, 1.0)
    s_range = 0.0 if range_pos > 0.90 else (10.0 if range_pos >= 0.10 else 5.0)

    tos = (0.35 * s_winst) + (0.30 * s_liq) + (0.20 * s_rev) + (0.15 * s_range)

    return {
        "model": "Hybrid 4-Layer Scoring Engine",
        "p_buy_max": p_buy,
        "p_sell_list": p_sell,
        "ea_tax": int(p_sell * 0.05),
        "net_profit": int(net_profit),
        "net_roi_pct": round(net_roi * 100, 2),
        "prob_sold_1h": f"{round(p_sold_1h * 100, 1)}%",
        "sub_scores": {
            "profit_score_35pct": round(s_winst, 2),
            "liquidity_score_30pct": round(s_liq, 2),
            "reversion_score_20pct": round(s_rev, 2),
            "range_score_15pct": round(s_range, 2),
        },
        "trade_opportunity_score_0_to_10": round(tos, 2),
        "trade_decision": "EXECUTE" if (tos >= 7.0 and net_profit >= min_abs_profit) else "PASS"
    }

# ==============================================================================
# 2. SOURCE CODE GENERATOR (Outputs clean standalone files to user directory)
# ==============================================================================

PY_MODULE_TEMPLATE = '''"""
FC 26 Pricing Engine (Generated Standalone Module)
"""
import math

def get_fc_tick(price: float) -> int:
    if price < 1000: return 50
    if price < 10000: return 100
    if price < 50000: return 250
    if price < 100000: return 500
    return 1000

def round_to_tick(price: float, round_down: bool = True) -> int:
    tick = get_fc_tick(price)
    return int(math.floor(price / tick) * tick) if round_down else int(math.ceil(price / tick) * tick)

def calc_opportunity(card: dict, inventory_q: int = 0, account_budget: float = 1_000_000, hours_to_event: float = 4.0) -> dict:
    low_bin = float(card['lowBIN'])
    avg_24 = float(card['avg24'])
    min_24 = float(card['min24'])
    max_24 = float(card['max24'])
    trend_pct = float(card.get('trend_pct', 0.0))
    listings_hr = float(card['listings_per_hour'])
    sales_hr = float(card['sales_per_hour'])
    price_min_cap = float(card['price_min_range'])
    price_max_cap = float(card['price_max_range'])

    sigma = (math.log(max_24) - math.log(min_24)) / 1.665 if max_24 > min_24 and min_24 > 0 else 0.05
    mu_target = avg_24 * (1.0 + (0.3 * (trend_pct / 100.0)))
    fill_rate = sales_hr / max(listings_hr, 1.0)
    p_sold_1h = 1.0 - math.exp(-fill_rate)
    kappa = 1.0 / max(fill_rate, 0.05)

    gamma = max(0.05, min(0.8, 100000 / max(account_budget, 10000)))
    time_factor = max(hours_to_event, 0.2)

    r = low_bin - (inventory_q * gamma * (sigma ** 2) * (1.0 / time_factor) * low_bin)
    spread_half = (1.0 / gamma) * math.log(1.0 + (gamma / kappa)) * low_bin * 0.1
    p_sell = min(round_to_tick(max(r + spread_half, mu_target * 0.98) / 0.95, round_down=False), int(price_max_cap))

    min_abs_profit = 350.0 if low_bin < 10000 else 600.0
    p_buy = max(round_to_tick(((p_sell * 0.95) - min_abs_profit) / 1.05, round_down=True), int(price_min_cap))

    net_profit = (p_sell * 0.95) - p_buy
    net_roi = (net_profit / p_buy) if p_buy > 0 else 0

    s_winst = max(0.0, min(10.0, ((net_roi - 0.04) / 0.10) * 10.0))
    s_liq = max(0.0, min(10.0, (0.6 * p_sold_1h + 0.4 * min(sales_hr / 40.0, 1.0)) * 10.0))
    z_score = (low_bin - avg_24) / max((max_24 - min_24) / 4.0, 1.0)
    s_rev = max(0.0, min(10.0, 5.0 - (2.5 * z_score) + (0.2 * trend_pct)))
    range_pos = (low_bin - price_min_cap) / max(price_max_cap - price_min_cap, 1.0)
    s_range = 0.0 if range_pos > 0.90 else (10.0 if range_pos >= 0.10 else 5.0)

    tos = (0.35 * s_winst) + (0.30 * s_liq) + (0.20 * s_rev) + (0.15 * s_range)

    return {
        "p_koop_snipe_max": p_buy,
        "p_verkoop_list": p_sell,
        "net_profit": int(net_profit),
        "net_roi_pct": round(net_roi * 100, 2),
        "opportunity_score": round(tos, 2),
        "trade_decision": "EXECUTE" if (tos >= 7.0 and net_profit >= min_abs_profit) else "PASS"
    }
'''

JS_MODULE_TEMPLATE = '''/**
 * FC 26 Pricing Engine (Generated Standalone Module)
 */
class FC26PricingEngine {
    static getPriceTick(price) {
        if (price < 1000) return 50;
        if (price < 10000) return 100;
        if (price < 50000) return 250;
        if (price < 100000) return 500;
        return 1000;
    }

    static roundToTick(price, roundDown = true) {
        const tick = this.getPriceTick(price);
        return roundDown ? Math.floor(price / tick) * tick : Math.ceil(price / tick) * tick;
    }

    static analyzeOpportunity(card, inventoryQ = 0, accountBudget = 1000000, hoursToEvent = 4.0) {
        const lowBIN = Number(card.lowBIN);
        const avg24 = Number(card.avg24);
        const min24 = Number(card.min24);
        const max24 = Number(card.max24);
        const trendPct = Number(card.trend_pct || 0);
        const listingsHr = Number(card.listings_per_hour);
        const salesHr = Number(card.sales_per_hour);
        const minCap = Number(card.price_min_range);
        const maxCap = Number(card.price_max_range);

        const sigma = (max24 > min24 && min24 > 0) ? (Math.log(max24) - Math.log(min24)) / 1.665 : 0.05;
        const muTarget = avg24 * (1.0 + (0.3 * (trendPct / 100.0)));
        const fillRate = salesHr / Math.max(listingsHr, 1.0);
        const pSold1h = 1.0 - Math.exp(-fillRate);
        const kappa = 1.0 / Math.max(fillRate, 0.05);

        const gamma = Math.max(0.05, Math.min(0.8, 100000 / Math.max(accountBudget, 10000)));
        const timeFactor = Math.max(hoursToEvent, 0.2);

        const r = lowBIN - (inventoryQ * gamma * Math.pow(sigma, 2) * (1.0 / timeFactor) * lowBIN);
        const spreadHalf = (1.0 / gamma) * Math.log(1.0 + (gamma / kappa)) * lowBIN * 0.1;
        let pSell = Math.min(this.roundToTick(Math.max(r + spreadHalf, muTarget * 0.98) / 0.95, false), maxCap);

        const minAbsProfit = lowBIN < 10000 ? 350 : 600;
        let pBuy = Math.max(this.roundToTick(((pSell * 0.95) - minAbsProfit) / 1.05, true), minCap);

        const netProfit = (pSell * 0.95) - pBuy;
        const netRoi = pBuy > 0 ? (netProfit / pBuy) : 0;

        const sWinst = Math.max(0, Math.min(10, ((netRoi - 0.04) / 0.10) * 10));
        const sLiq = Math.max(0, Math.min(10, (0.6 * pSold1h + 0.4 * Math.min(salesHr / 40, 1)) * 10));
        const zScore = (lowBIN - avg24) / Math.max((max24 - min24) / 4, 1);
        const sRev = Math.max(0, Math.min(10, 5.0 - (2.5 * zScore) + (0.2 * trendPct)));
        const rangePos = (lowBIN - minCap) / Math.max(maxCap - minCap, 1);
        const sRange = rangePos > 0.90 ? 0 : (rangePos >= 0.10 ? 10 : 5);

        const tos = (0.35 * sWinst) + (0.30 * sLiq) + (0.20 * sRev) + (0.15 * sRange);

        return {
            p_koop_snipe_max: pBuy,
            p_verkoop_list: pSell,
            net_profit: Math.floor(netProfit),
            net_roi_pct: (netRoi * 100).toFixed(2),
            opportunity_score: Number(tos.toFixed(2)),
            trade_decision: (tos >= 7.0 && netProfit >= minAbsProfit) ? "EXECUTE" : "PASS"
        };
    }
}

if (typeof module !== 'undefined') {
    module.exports = { FC26PricingEngine };
}
'''

def write_files_to_directory(target_dir: str):
    """Creates the directory and writes the standalone engine files."""
    os.makedirs(target_dir, exist_ok=True)

    py_path = os.path.join(target_dir, "fc26_pricing_engine.py")
    js_path = os.path.join(target_dir, "fc26_pricing_engine.js")

    with open(py_path, "w", encoding="utf-8") as f:
        f.write(PY_MODULE_TEMPLATE)
    with open(js_path, "w", encoding="utf-8") as f:
        f.write(JS_MODULE_TEMPLATE)

    print(f"\n[OK] Standalone modules generated:")
    print(f"  -> Python:     {py_path}")
    print(f"  -> JavaScript: {js_path}")

# ==============================================================================
# 3. INTERACTIVE CLI RUNNER
# ==============================================================================

def prompt_variable(name: str, desc: str, format_hint: str, default_val: Any) -> Any:
    """Helper to prompt the user with explanations and default fallbacks."""
    print(f"\n[-] {name.upper()}")
    print(f"    Uitleg:   {desc}")
    print(f"    Formaat:  {format_hint}")
    user_input = input(f"    Invoer (Druk Enter voor standaard: {default_val}): ").strip()

    if user_input == "":
        return default_val
    try:
        if isinstance(default_val, int):
            return int(user_input)
        elif isinstance(default_val, float):
            return float(user_input)
        return user_input
    except ValueError:
        print(f"    [!] Ongeldig formaat. Standaardwaarde {default_val} wordt gebruikt.")
        return default_val

def main():
    print("=" * 75)
    print("  FC 26 QUANTITATIVE PRICING & MARKET MAKING TEST SUITE")
    print("=" * 75)

    # 1. Output directory selection
    target_dir = input("\n[1/3] Voer het directory pad in waar de code moet worden opgeslagen:\n(bijv. './fc_engine' of 'C:/dev/fc26'): ").strip()
    if not target_dir:
        target_dir = "./fc_engine"
    write_files_to_directory(target_dir)

    # 2. Interactive Loop
    while True:
        print("\n" + "=" * 75)
        print("[2/3] Kies het model dat je wilt testen:")
        print("  1. Avellaneda-Stoikov (Voorraadrisico & Volatiliteit)")
        print("  2. Hazard Rate & Expected Value (Orderflow & Verkoopkans)")
        print("  3. Ornstein-Uhlenbeck (Mean Reversion & Trend Dips)")
        print("  4. Hybride 4-Laags Scoring Engine (TOS 0-10 Score + Besluit)")
        print("  5. Afsluiten")
        print("=" * 75)

        choice = input("Maak een keuze (1-5): ").strip()

        if choice == "5":
            print("\nAfsluiten... Succes op de transfermarkt!")
            break

        print("\n[3/3] Configureer de parameters voor de test:")

        if choice == "1":
            low_bin = prompt_variable("lowBIN", "Actuele laagste Buy-Now prijs op de markt", "Integer (bijv. 45000)", 45000)
            min_24h = prompt_variable("min24", "Laagste prijs in de afgelopen 24 uur (FUTBIN)", "Integer (bijv. 42000)", 42000)
            max_24h = prompt_variable("max24", "Hoogste prijs in de afgelopen 24 uur (FUTBIN)", "Integer (bijv. 52000)", 52000)
            sales_hr = prompt_variable("sales_per_hour", "Aantal succesvolle verkopen per uur", "Float/Int (bijv. 60)", 60.0)
            listings_hr = prompt_variable("listings_per_hour", "Aantal nieuwe listings per uur", "Float/Int (bijv. 75)", 75.0)
            inventory_q = prompt_variable("inventory_q", "Aantal kaarten dat je al bezit van deze speler", "Integer (bijv. 0, 1, 3)", 0)
            gamma = prompt_variable("gamma", "Risico-aversie parameter (hoger = angstiger voor drops)", "Float tussen 0.01 en 0.8", 0.1)
            time_event = prompt_variable("hours_to_event", "Aantal uren tot de volgende 19:00 content drop", "Float (bijv. 3.5)", 4.0)

            res = run_avellaneda_stoikov(
                low_bin=low_bin, min_24h=min_24h, max_24h=max_24h,
                sales_hr=sales_hr, listings_hr=listings_hr,
                inventory_q=inventory_q, gamma=gamma, time_to_event_hrs=time_event
            )

        elif choice == "2":
            low_bin = prompt_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 35000)", 35000)
            sales_hr = prompt_variable("sales_per_hour", "Aantal gekochte kaarten per uur", "Float (bijv. 80)", 80.0)
            listings_hr = prompt_variable("listings_per_hour", "Aantal aangeboden kaarten per uur", "Float (bijv. 90)", 90.0)
            target_roi = prompt_variable("target_roi", "Gewenste netto return on investment (bijv. 0.08 = 8%)", "Float (bijv. 0.08)", 0.08)
            holding_hours = prompt_variable("holding_hours", "Maximale gewenste listing duur in uren", "Float (bijv. 1.0)", 1.0)

            res = run_hazard_rate_ev(
                low_bin=low_bin, sales_hr=sales_hr, listings_hr=listings_hr,
                target_roi=target_roi, holding_hours=holding_hours
            )

        elif choice == "3":
            low_bin = prompt_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 65000)", 65000)
            avg_24h = prompt_variable("avg24", "Gemiddelde 24h prijs op FUTBIN", "Integer (bijv. 72000)", 72000)
            min_24h = prompt_variable("min24", "24h Laagste prijs", "Integer (bijv. 64000)", 64000)
            max_24h = prompt_variable("max24", "24h Hoogste prijs", "Integer (bijv. 78000)", 78000)
            trend_pct = prompt_variable("trend_pct", "Trend percentage van FUTBIN (bijv. -2.5)", "Float (bijv. -1.5)", -1.5)
            diff_pct = prompt_variable("diff_pct", "Verschil percentage t.o.v. gisteren", "Float (bijv. 0.8)", 0.8)

            res = run_ornstein_uhlenbeck(
                low_bin=low_bin, avg_24h=avg_24h, min_24h=min_24h,
                max_24h=max_24h, trend_pct=trend_pct, diff_pct=diff_pct
            )

        elif choice == "4":
            card = {
                'lowBIN': prompt_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 55000)", 55000),
                'avg24': prompt_variable("avg24", "24-uurs daggemiddelde", "Integer (bijv. 60000)", 60000),
                'min24': prompt_variable("min24", "24-uurs laagste prijs", "Integer (bijv. 53000)", 53000),
                'max24': prompt_variable("max24", "24-uurs hoogste prijs", "Integer (bijv. 66000)", 66000),
                'trend_pct': prompt_variable("trend_pct", "FUTBIN Trend %", "Float (bijv. 2.1)", 2.1),
                'listings_per_hour': prompt_variable("listings_per_hour", "Aantal listings per uur", "Float (bijv. 95)", 95.0),
                'sales_per_hour': prompt_variable("sales_per_hour", "Aantal verkopen per uur", "Float (bijv. 85)", 85.0),
                'price_min_range': prompt_variable("price_min_range", "EA Price Band Min", "Integer (bijv. 3000)", 3000),
                'price_max_range': prompt_variable("price_max_range", "EA Price Band Max", "Integer (bijv. 120000)", 120000)
            }
            inv_q = prompt_variable("inventory_q", "Aantal kaarten van deze speler in je club/trade pile", "Integer", 0)
            budget = prompt_variable("account_budget", "Totaal aantal munten op je account", "Integer (bijv. 1500000)", 1500000)
            hours_event = prompt_variable("hours_to_event", "Uren tot volgende content reset", "Float (bijv. 3.0)", 3.0)

            res = run_hybrid_tos(card, inventory_q=inv_q, account_budget=budget, hours_to_event=hours_event)

        else:
            print("[!] Ongeldige keuze.")
            continue

        # 3. Print Results
        print("\n" + "=" * 75)
        print(f" RESULTATEN: {res.get('model', 'Model Test')}")
        print("=" * 75)
        print(json.dumps(res, indent=4))
        print("=" * 75)

        input("\nDruk op Enter om terug te gaan naar het hoofdmenu...")

if __name__ == "__main__":
    main()
```

---

### Hoe je dit gebruikt:

1. Kopieer de bovenstaande code en sla hem op als bijvoorbeeld `fc_pricing_runner.py`.
2. Voer het script uit in je terminal:
   ```bash
   python fc_pricing_runner.py
   ```
3. Het script vraagt als eerste naar een directory (bijvoorbeeld `./fc_pricing`). Het maakt deze direct aan en genereert twee productiegerijpte modules:
   - **`fc26_pricing_engine.py`** (klaar om te importeren in je Python bots / analytics pipeline).
   - **`fc26_pricing_engine.js`** (klaar om te gebruiken in Node.js of direct in de browser console/Tampermonkey scripts).
4. Daarna kom je in het interactieve menu waar je elk model los of gecombineerd kunt testen door simpelweg de getallen van een speler in te voeren.
