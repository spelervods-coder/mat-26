Here is a complete, interactive Python CLI script (called \*\*`fc\_pricing\_runner.py`\*\*) that implements everything discussed:



1\. Asks for an \*\*output directory path\*\* and automatically writes modular Python and JavaScript engine files there.

2\. Provides an interactive menu to choose which model you want to test:

&#x20;  \* \*\*Model 1:\*\* Avellaneda-Stoikov (Inventory \& Volatility)

&#x20;  \* \*\*Model 2:\*\* Hazard Rate \& Expected Value (Order Flow \& Survival)

&#x20;  \* \*\*Model 3:\*\* Ornstein-Uhlenbeck (Mean Reversion \& Trend)

&#x20;  \* \*\*Model 4:\*\* The Complete Hybrid 4-Layer Scoring Engine (TOS 0–10)

3\. Prompts for every variable with \*\*clear explanations, expected formats, and sensible default values\*\* (press \*Enter\* to keep defaults).

4\. Computes the results live and displays a formatted trade breakdown (Prices, EA Tax, Net Profit, ROI %, Fill Rate, and Trade Decision).



\---



\### Python Script: `fc\_pricing\_runner.py`



Save this file and run it using: `python fc\_pricing\_runner.py`



```python

\#!/usr/bin/env python3

"""

FC 26 Transfer Market Pricing \& Opportunity CLI Suite

Supports Avellaneda-Stoikov, Hazard/EV, Ornstein-Uhlenbeck, and Hybrid TOS Engine.

"""



import os

import sys

import math

import json



\# ==============================================================================

\# 1. CORE QUANTITATIVE ALGORITHMS (Python Implementation)

\# ==============================================================================



def get\_fc\_tick(price: float) -> int:

&#x20;   """Standard FC 26 transfer market price tick increments."""

&#x20;   if price < 1000:

&#x20;       return 50

&#x20;   elif price < 10000:

&#x20;       return 100

&#x20;   elif price < 50000:

&#x20;       return 250

&#x20;   elif price < 100000:

&#x20;       return 500

&#x20;   else:

&#x20;       return 1000



def round\_to\_tick(price: float, round\_down: bool = True) -> int:

&#x20;   """Clamps a raw float price to valid FC transfer market ticks."""

&#x20;   tick = get\_fc\_tick(price)

&#x20;   if round\_down:

&#x20;       return int(math.floor(price / tick) \* tick)

&#x20;   return int(math.ceil(price / tick) \* tick)



def calc\_parkinson\_volatility(min\_24h: float, max\_24h: float) -> float:

&#x20;   """Estimates Parkinson continuous volatility from 24h high/low."""

&#x20;   if max\_24h > min\_24h and min\_24h > 0:

&#x20;       return (math.log(max\_24h) - math.log(min\_24h)) / 1.665

&#x20;   return 0.05



def run\_avellaneda\_stoikov(

&#x20;   low\_bin: float,

&#x20;   min\_24h: float,

&#x20;   max\_24h: float,

&#x20;   sales\_hr: float,

&#x20;   listings\_hr: float,

&#x20;   inventory\_q: int = 0,

&#x20;   gamma: float = 0.1,

&#x20;   time\_to\_event\_hrs: float = 4.0,

&#x20;   price\_min\_cap: float = 200,

&#x20;   price\_max\_cap: float = 1000000

):

&#x20;   sigma = calc\_parkinson\_volatility(min\_24h, max\_24h)

&#x20;   fill\_rate = sales\_hr / max(listings\_hr, 1.0)

&#x20;   kappa = 1.0 / max(fill\_rate, 0.05)

&#x20;   time\_factor = max(time\_to\_event\_hrs, 0.2)



&#x20;   # Reservation price penalized by inventory and event horizon

&#x20;   r = low\_bin - (inventory\_q \* gamma \* (sigma \*\* 2) \* (1.0 / time\_factor) \* low\_bin)

&#x20;   

&#x20;   # Half spread

&#x20;   spread\_half = (1.0 / gamma) \* math.log(1.0 + (gamma / kappa)) \* (low\_bin \* 0.08)

&#x20;   

&#x20;   raw\_sell = r + spread\_half

&#x20;   p\_sell = round\_to\_tick(raw\_sell / 0.95, round\_down=False) # 5% EA tax adjusted

&#x20;   p\_sell = max(int(price\_min\_cap), min(p\_sell, int(price\_max\_cap)))



&#x20;   raw\_buy = r - spread\_half

&#x20;   p\_buy = round\_to\_tick(min(raw\_buy, p\_sell \* 0.95 - 350), round\_down=True)

&#x20;   p\_buy = max(int(price\_min\_cap), min(p\_buy, int(price\_max\_cap)))



&#x20;   net\_profit = (p\_sell \* 0.95) - p\_buy

&#x20;   roi = (net\_profit / p\_buy \* 100) if p\_buy > 0 else 0



&#x20;   return {

&#x20;       "model": "Avellaneda-Stoikov (Inventory \& Risk)",

&#x20;       "sigma\_volatility": round(sigma, 4),

&#x20;       "reservation\_price": int(r),

&#x20;       "p\_buy\_max": p\_buy,

&#x20;       "p\_sell\_list": p\_sell,

&#x20;       "ea\_tax": int(p\_sell \* 0.05),

&#x20;       "net\_profit": int(net\_profit),

&#x20;       "net\_roi\_pct": round(roi, 2)

&#x20;   }



def run\_hazard\_rate\_ev(

&#x20;   low\_bin: float,

&#x20;   sales\_hr: float,

&#x20;   listings\_hr: float,

&#x20;   target\_roi: float = 0.08,

&#x20;   holding\_hours: float = 1.0,

&#x20;   price\_min\_cap: float = 200,

&#x20;   price\_max\_cap: float = 1000000

):

&#x20;   fill\_rate = sales\_hr / max(listings\_hr, 1.0)

&#x20;   p\_fill = 1.0 - math.exp(-fill\_rate \* holding\_hours)



&#x20;   # Sell strategy: if high velocity list slightly above lowBIN, else match lowBIN

&#x20;   if fill\_rate > 0.85:

&#x20;       target\_sell = low\_bin \* 1.03

&#x20;   else:

&#x20;       target\_sell = low\_bin



&#x20;   p\_sell = round\_to\_tick(target\_sell, round\_down=False)

&#x20;   p\_sell = max(int(price\_min\_cap), min(p\_sell, int(price\_max\_cap)))



&#x20;   net\_revenue = p\_sell \* 0.95

&#x20;   # Max buy constrained by Target ROI and execution likelihood

&#x20;   raw\_buy = (net\_revenue \* p\_fill) / (1.0 + target\_roi)

&#x20;   p\_buy = round\_to\_tick(raw\_buy, round\_down=True)

&#x20;   p\_buy = max(int(price\_min\_cap), min(p\_buy, int(price\_max\_cap)))



&#x20;   net\_profit = (p\_sell \* 0.95) - p\_buy

&#x20;   roi = (net\_profit / p\_buy \* 100) if p\_buy > 0 else 0



&#x20;   return {

&#x20;       "model": "Hazard Rate \& Expected Value",

&#x20;       "fill\_rate\_ratio": round(fill\_rate, 3),

&#x20;       "prob\_sold\_in\_window": f"{round(p\_fill \* 100, 1)}%",

&#x20;       "p\_buy\_max": p\_buy,

&#x20;       "p\_sell\_list": p\_sell,

&#x20;       "ea\_tax": int(p\_sell \* 0.05),

&#x20;       "net\_profit": int(net\_profit),

&#x20;       "net\_roi\_pct": round(roi, 2)

&#x20;   }



def run\_ornstein\_uhlenbeck(

&#x20;   low\_bin: float,

&#x20;   avg\_24h: float,

&#x20;   min\_24h: float,

&#x20;   max\_24h: float,

&#x20;   trend\_pct: float = 0.0,

&#x20;   diff\_pct: float = 0.0,

&#x20;   price\_min\_cap: float = 200,

&#x20;   price\_max\_cap: float = 1000000

):

&#x20;   sigma\_norm = max((max\_24h - min\_24h) / 4.0, 1.0)

&#x20;   mu\_target = avg\_24h \* (1.0 + 0.5 \* (trend\_pct / 100.0) + 0.2 \* (diff\_pct / 100.0))

&#x20;   z\_score = (low\_bin - mu\_target) / sigma\_norm



&#x20;   # Listing targets the mean reversion level

&#x20;   p\_sell = round\_to\_tick(max(mu\_target, low\_bin \* 1.02), round\_down=False)

&#x20;   p\_sell = max(int(price\_min\_cap), min(p\_sell, int(price\_max\_cap)))



&#x20;   # Buy target triggers in oversold conditions

&#x20;   raw\_buy = min(low\_bin, mu\_target - 0.5 \* sigma\_norm)

&#x20;   # Hard EA tax margin filter

&#x20;   raw\_buy = min(raw\_buy, (p\_sell \* 0.95) / 1.06)

&#x20;   p\_buy = round\_to\_tick(raw\_buy, round\_down=True)

&#x20;   p\_buy = max(int(price\_min\_cap), min(p\_buy, int(price\_max\_cap)))



&#x20;   net\_profit = (p\_sell \* 0.95) - p\_buy

&#x20;   roi = (net\_profit / p\_buy \* 100) if p\_buy > 0 else 0



&#x20;   return {

&#x20;       "model": "Ornstein-Uhlenbeck Mean Reversion",

&#x20;       "z\_score": round(z\_score, 2),

&#x20;       "mean\_reversion\_target": int(mu\_target),

&#x20;       "p\_buy\_max": p\_buy,

&#x20;       "p\_sell\_list": p\_sell,

&#x20;       "ea\_tax": int(p\_sell \* 0.05),

&#x20;       "net\_profit": int(net\_profit),

&#x20;       "net\_roi\_pct": round(roi, 2)

&#x20;   }



def run\_hybrid\_tos(card\_dict: dict, inventory\_q: int = 0, account\_budget: float = 1\_000\_000, hours\_to\_event: float = 4.0):

&#x20;   low\_bin = float(card\_dict\['lowBIN'])

&#x20;   avg\_24 = float(card\_dict\['avg24'])

&#x20;   min\_24 = float(card\_dict\['min24'])

&#x20;   max\_24 = float(card\_dict\['max24'])

&#x20;   trend\_pct = float(card\_dict.get('trend\_pct', 0.0))

&#x20;   listings\_hr = float(card\_dict\['listings\_per\_hour'])

&#x20;   sales\_hr = float(card\_dict\['sales\_per\_hour'])

&#x20;   price\_min\_cap = float(card\_dict\['price\_min\_range'])

&#x20;   price\_max\_cap = float(card\_dict\['price\_max\_range'])



&#x20;   sigma = calc\_parkinson\_volatility(min\_24, max\_24)

&#x20;   mu\_target = avg\_24 \* (1.0 + (0.3 \* (trend\_pct / 100.0)))

&#x20;   fill\_rate = sales\_hr / max(listings\_hr, 1.0)

&#x20;   p\_sold\_1h = 1.0 - math.exp(-fill\_rate)

&#x20;   kappa = 1.0 / max(fill\_rate, 0.05)



&#x20;   gamma = max(0.05, min(0.8, 100000 / max(account\_budget, 10000)))

&#x20;   time\_factor = max(hours\_to\_event, 0.2)



&#x20;   reservation\_price = low\_bin - (inventory\_q \* gamma \* (sigma \*\* 2) \* (1.0 / time\_factor) \* low\_bin)

&#x20;   spread\_half = (1.0 / gamma) \* math.log(1.0 + (gamma / kappa)) \* low\_bin \* 0.1

&#x20;   target\_sell\_raw = max(reservation\_price + spread\_half, mu\_target \* 0.98)

&#x20;   

&#x20;   p\_sell = round\_to\_tick(target\_sell\_raw / 0.95, round\_down=False)

&#x20;   p\_sell = min(p\_sell, int(price\_max\_cap))



&#x20;   net\_sell\_revenue = p\_sell \* 0.95

&#x20;   min\_abs\_profit = 350.0 if low\_bin < 10000 else 600.0

&#x20;   target\_roi = 0.05



&#x20;   target\_buy\_raw = (net\_sell\_revenue - min\_abs\_profit) / (1.0 + target\_roi)

&#x20;   p\_buy = round\_to\_tick(target\_buy\_raw, round\_down=True)

&#x20;   p\_buy = max(p\_buy, int(price\_min\_cap))



&#x20;   net\_profit = (p\_sell \* 0.95) - p\_buy

&#x20;   net\_roi = (net\_profit / p\_buy) if p\_buy > 0 else 0



&#x20;   s\_winst = max(0.0, min(10.0, ((net\_roi - 0.04) / 0.10) \* 10.0))

&#x20;   s\_liq = max(0.0, min(10.0, (0.6 \* p\_sold\_1h + 0.4 \* min(sales\_hr / 40.0, 1.0)) \* 10.0))

&#x20;   z\_score = (low\_bin - avg\_24) / max((max\_24 - min\_24) / 4.0, 1.0)

&#x20;   s\_rev = max(0.0, min(10.0, 5.0 - (2.5 \* z\_score) + (0.2 \* trend\_pct)))

&#x20;   range\_pos = (low\_bin - price\_min\_cap) / max(price\_max\_cap - price\_min\_cap, 1.0)

&#x20;   s\_range = 0.0 if range\_pos > 0.90 else (10.0 if range\_pos >= 0.10 else 5.0)



&#x20;   tos = (0.35 \* s\_winst) + (0.30 \* s\_liq) + (0.20 \* s\_rev) + (0.15 \* s\_range)



&#x20;   return {

&#x20;       "model": "Hybrid 4-Layer Scoring Engine",

&#x20;       "p\_buy\_max": p\_buy,

&#x20;       "p\_sell\_list": p\_sell,

&#x20;       "ea\_tax": int(p\_sell \* 0.05),

&#x20;       "net\_profit": int(net\_profit),

&#x20;       "net\_roi\_pct": round(net\_roi \* 100, 2),

&#x20;       "prob\_sold\_1h": f"{round(p\_sold\_1h \* 100, 1)}%",

&#x20;       "sub\_scores": {

&#x20;           "profit\_score\_35pct": round(s\_winst, 2),

&#x20;           "liquidity\_score\_30pct": round(s\_liq, 2),

&#x20;           "reversion\_score\_20pct": round(s\_rev, 2),

&#x20;           "range\_score\_15pct": round(s\_range, 2),

&#x20;       },

&#x20;       "trade\_opportunity\_score\_0\_to\_10": round(tos, 2),

&#x20;       "trade\_decision": "EXECUTE" if (tos >= 7.0 and net\_profit >= min\_abs\_profit) else "PASS"

&#x20;   }



\# ==============================================================================

\# 2. SOURCE CODE GENERATOR (Outputs clean standalone files to user directory)

\# ==============================================================================



PY\_MODULE\_TEMPLATE = '''"""

FC 26 Pricing Engine (Generated Standalone Module)

"""

import math



def get\_fc\_tick(price: float) -> int:

&#x20;   if price < 1000: return 50

&#x20;   if price < 10000: return 100

&#x20;   if price < 50000: return 250

&#x20;   if price < 100000: return 500

&#x20;   return 1000



def round\_to\_tick(price: float, round\_down: bool = True) -> int:

&#x20;   tick = get\_fc\_tick(price)

&#x20;   return int(math.floor(price / tick) \* tick) if round\_down else int(math.ceil(price / tick) \* tick)



def calc\_opportunity(card: dict, inventory\_q: int = 0, account\_budget: float = 1\_000\_000, hours\_to\_event: float = 4.0) -> dict:

&#x20;   low\_bin = float(card\['lowBIN'])

&#x20;   avg\_24 = float(card\['avg24'])

&#x20;   min\_24 = float(card\['min24'])

&#x20;   max\_24 = float(card\['max24'])

&#x20;   trend\_pct = float(card.get('trend\_pct', 0.0))

&#x20;   listings\_hr = float(card\['listings\_per\_hour'])

&#x20;   sales\_hr = float(card\['sales\_per\_hour'])

&#x20;   price\_min\_cap = float(card\['price\_min\_range'])

&#x20;   price\_max\_cap = float(card\['price\_max\_range'])



&#x20;   sigma = (math.log(max\_24) - math.log(min\_24)) / 1.665 if max\_24 > min\_24 and min\_24 > 0 else 0.05

&#x20;   mu\_target = avg\_24 \* (1.0 + (0.3 \* (trend\_pct / 100.0)))

&#x20;   fill\_rate = sales\_hr / max(listings\_hr, 1.0)

&#x20;   p\_sold\_1h = 1.0 - math.exp(-fill\_rate)

&#x20;   kappa = 1.0 / max(fill\_rate, 0.05)



&#x20;   gamma = max(0.05, min(0.8, 100000 / max(account\_budget, 10000)))

&#x20;   time\_factor = max(hours\_to\_event, 0.2)



&#x20;   r = low\_bin - (inventory\_q \* gamma \* (sigma \*\* 2) \* (1.0 / time\_factor) \* low\_bin)

&#x20;   spread\_half = (1.0 / gamma) \* math.log(1.0 + (gamma / kappa)) \* low\_bin \* 0.1

&#x20;   p\_sell = min(round\_to\_tick(max(r + spread\_half, mu\_target \* 0.98) / 0.95, round\_down=False), int(price\_max\_cap))



&#x20;   min\_abs\_profit = 350.0 if low\_bin < 10000 else 600.0

&#x20;   p\_buy = max(round\_to\_tick(((p\_sell \* 0.95) - min\_abs\_profit) / 1.05, round\_down=True), int(price\_min\_cap))



&#x20;   net\_profit = (p\_sell \* 0.95) - p\_buy

&#x20;   net\_roi = (net\_profit / p\_buy) if p\_buy > 0 else 0



&#x20;   s\_winst = max(0.0, min(10.0, ((net\_roi - 0.04) / 0.10) \* 10.0))

&#x20;   s\_liq = max(0.0, min(10.0, (0.6 \* p\_sold\_1h + 0.4 \* min(sales\_hr / 40.0, 1.0)) \* 10.0))

&#x20;   z\_score = (low\_bin - avg\_24) / max((max\_24 - min\_24) / 4.0, 1.0)

&#x20;   s\_rev = max(0.0, min(10.0, 5.0 - (2.5 \* z\_score) + (0.2 \* trend\_pct)))

&#x20;   range\_pos = (low\_bin - price\_min\_cap) / max(price\_max\_cap - price\_min\_cap, 1.0)

&#x20;   s\_range = 0.0 if range\_pos > 0.90 else (10.0 if range\_pos >= 0.10 else 5.0)



&#x20;   tos = (0.35 \* s\_winst) + (0.30 \* s\_liq) + (0.20 \* s\_rev) + (0.15 \* s\_range)



&#x20;   return {

&#x20;       "p\_koop\_snipe\_max": p\_buy,

&#x20;       "p\_verkoop\_list": p\_sell,

&#x20;       "net\_profit": int(net\_profit),

&#x20;       "net\_roi\_pct": round(net\_roi \* 100, 2),

&#x20;       "opportunity\_score": round(tos, 2),

&#x20;       "trade\_decision": "EXECUTE" if (tos >= 7.0 and net\_profit >= min\_abs\_profit) else "PASS"

&#x20;   }

'''



JS\_MODULE\_TEMPLATE = '''/\*\*

&#x20;\* FC 26 Pricing Engine (Generated Standalone Module)

&#x20;\*/

class FC26PricingEngine {

&#x20;   static getPriceTick(price) {

&#x20;       if (price < 1000) return 50;

&#x20;       if (price < 10000) return 100;

&#x20;       if (price < 50000) return 250;

&#x20;       if (price < 100000) return 500;

&#x20;       return 1000;

&#x20;   }



&#x20;   static roundToTick(price, roundDown = true) {

&#x20;       const tick = this.getPriceTick(price);

&#x20;       return roundDown ? Math.floor(price / tick) \* tick : Math.ceil(price / tick) \* tick;

&#x20;   }



&#x20;   static analyzeOpportunity(card, inventoryQ = 0, accountBudget = 1000000, hoursToEvent = 4.0) {

&#x20;       const lowBIN = Number(card.lowBIN);

&#x20;       const avg24 = Number(card.avg24);

&#x20;       const min24 = Number(card.min24);

&#x20;       const max24 = Number(card.max24);

&#x20;       const trendPct = Number(card.trend\_pct || 0);

&#x20;       const listingsHr = Number(card.listings\_per\_hour);

&#x20;       const salesHr = Number(card.sales\_per\_hour);

&#x20;       const minCap = Number(card.price\_min\_range);

&#x20;       const maxCap = Number(card.price\_max\_range);



&#x20;       const sigma = (max24 > min24 \&\& min24 > 0) ? (Math.log(max24) - Math.log(min24)) / 1.665 : 0.05;

&#x20;       const muTarget = avg24 \* (1.0 + (0.3 \* (trendPct / 100.0)));

&#x20;       const fillRate = salesHr / Math.max(listingsHr, 1.0);

&#x20;       const pSold1h = 1.0 - Math.exp(-fillRate);

&#x20;       const kappa = 1.0 / Math.max(fillRate, 0.05);



&#x20;       const gamma = Math.max(0.05, Math.min(0.8, 100000 / Math.max(accountBudget, 10000)));

&#x20;       const timeFactor = Math.max(hoursToEvent, 0.2);



&#x20;       const r = lowBIN - (inventoryQ \* gamma \* Math.pow(sigma, 2) \* (1.0 / timeFactor) \* lowBIN);

&#x20;       const spreadHalf = (1.0 / gamma) \* Math.log(1.0 + (gamma / kappa)) \* lowBIN \* 0.1;

&#x20;       let pSell = Math.min(this.roundToTick(Math.max(r + spreadHalf, muTarget \* 0.98) / 0.95, false), maxCap);



&#x20;       const minAbsProfit = lowBIN < 10000 ? 350 : 600;

&#x20;       let pBuy = Math.max(this.roundToTick(((pSell \* 0.95) - minAbsProfit) / 1.05, true), minCap);



&#x20;       const netProfit = (pSell \* 0.95) - pBuy;

&#x20;       const netRoi = pBuy > 0 ? (netProfit / pBuy) : 0;



&#x20;       const sWinst = Math.max(0, Math.min(10, ((netRoi - 0.04) / 0.10) \* 10));

&#x20;       const sLiq = Math.max(0, Math.min(10, (0.6 \* pSold1h + 0.4 \* Math.min(salesHr / 40, 1)) \* 10));

&#x20;       const zScore = (lowBIN - avg24) / Math.max((max24 - min24) / 4, 1);

&#x20;       const sRev = Math.max(0, Math.min(10, 5.0 - (2.5 \* zScore) + (0.2 \* trendPct)));

&#x20;       const rangePos = (lowBIN - minCap) / Math.max(maxCap - minCap, 1);

&#x20;       const sRange = rangePos > 0.90 ? 0 : (rangePos >= 0.10 ? 10 : 5);



&#x20;       const tos = (0.35 \* sWinst) + (0.30 \* sLiq) + (0.20 \* sRev) + (0.15 \* sRange);



&#x20;       return {

&#x20;           p\_koop\_snipe\_max: pBuy,

&#x20;           p\_verkoop\_list: pSell,

&#x20;           net\_profit: Math.floor(netProfit),

&#x20;           net\_roi\_pct: (netRoi \* 100).toFixed(2),

&#x20;           opportunity\_score: Number(tos.toFixed(2)),

&#x20;           trade\_decision: (tos >= 7.0 \&\& netProfit >= minAbsProfit) ? "EXECUTE" : "PASS"

&#x20;       };

&#x20;   }

}



if (typeof module !== 'undefined') {

&#x20;   module.exports = { FC26PricingEngine };

}

'''



def write\_files\_to\_directory(target\_dir: str):

&#x20;   """Creates the directory and writes the standalone engine files."""

&#x20;   os.makedirs(target\_dir, exist\_ok=True)

&#x20;   

&#x20;   py\_path = os.path.join(target\_dir, "fc26\_pricing\_engine.py")

&#x20;   js\_path = os.path.join(target\_dir, "fc26\_pricing\_engine.js")

&#x20;   

&#x20;   with open(py\_path, "w", encoding="utf-8") as f:

&#x20;       f.write(PY\_MODULE\_TEMPLATE)

&#x20;   with open(js\_path, "w", encoding="utf-8") as f:

&#x20;       f.write(JS\_MODULE\_TEMPLATE)

&#x20;       

&#x20;   print(f"\\n\[OK] Standalone modules generated:")

&#x20;   print(f"  -> Python:     {py\_path}")

&#x20;   print(f"  -> JavaScript: {js\_path}")



\# ==============================================================================

\# 3. INTERACTIVE CLI RUNNER

\# ==============================================================================



def prompt\_variable(name: str, desc: str, format\_hint: str, default\_val: Any) -> Any:

&#x20;   """Helper to prompt the user with explanations and default fallbacks."""

&#x20;   print(f"\\n\[-] {name.upper()}")

&#x20;   print(f"    Uitleg:   {desc}")

&#x20;   print(f"    Formaat:  {format\_hint}")

&#x20;   user\_input = input(f"    Invoer (Druk Enter voor standaard: {default\_val}): ").strip()

&#x20;   

&#x20;   if user\_input == "":

&#x20;       return default\_val

&#x20;   try:

&#x20;       if isinstance(default\_val, int):

&#x20;           return int(user\_input)

&#x20;       elif isinstance(default\_val, float):

&#x20;           return float(user\_input)

&#x20;       return user\_input

&#x20;   except ValueError:

&#x20;       print(f"    \[!] Ongeldig formaat. Standaardwaarde {default\_val} wordt gebruikt.")

&#x20;       return default\_val



def main():

&#x20;   print("=" \* 75)

&#x20;   print("  FC 26 QUANTITATIVE PRICING \& MARKET MAKING TEST SUITE")

&#x20;   print("=" \* 75)



&#x20;   # 1. Output directory selection

&#x20;   target\_dir = input("\\n\[1/3] Voer het directory pad in waar de code moet worden opgeslagen:\\n(bijv. './fc\_engine' of 'C:/dev/fc26'): ").strip()

&#x20;   if not target\_dir:

&#x20;       target\_dir = "./fc\_engine"

&#x20;   write\_files\_to\_directory(target\_dir)



&#x20;   # 2. Interactive Loop

&#x20;   while True:

&#x20;       print("\\n" + "=" \* 75)

&#x20;       print("\[2/3] Kies het model dat je wilt testen:")

&#x20;       print("  1. Avellaneda-Stoikov (Voorraadrisico \& Volatiliteit)")

&#x20;       print("  2. Hazard Rate \& Expected Value (Orderflow \& Verkoopkans)")

&#x20;       print("  3. Ornstein-Uhlenbeck (Mean Reversion \& Trend Dips)")

&#x20;       print("  4. Hybride 4-Laags Scoring Engine (TOS 0-10 Score + Besluit)")

&#x20;       print("  5. Afsluiten")

&#x20;       print("=" \* 75)



&#x20;       choice = input("Maak een keuze (1-5): ").strip()



&#x20;       if choice == "5":

&#x20;           print("\\nAfsluiten... Succes op de transfermarkt!")

&#x20;           break



&#x20;       print("\\n\[3/3] Configureer de parameters voor de test:")



&#x20;       if choice == "1":

&#x20;           low\_bin = prompt\_variable("lowBIN", "Actuele laagste Buy-Now prijs op de markt", "Integer (bijv. 45000)", 45000)

&#x20;           min\_24h = prompt\_variable("min24", "Laagste prijs in de afgelopen 24 uur (FUTBIN)", "Integer (bijv. 42000)", 42000)

&#x20;           max\_24h = prompt\_variable("max24", "Hoogste prijs in de afgelopen 24 uur (FUTBIN)", "Integer (bijv. 52000)", 52000)

&#x20;           sales\_hr = prompt\_variable("sales\_per\_hour", "Aantal succesvolle verkopen per uur", "Float/Int (bijv. 60)", 60.0)

&#x20;           listings\_hr = prompt\_variable("listings\_per\_hour", "Aantal nieuwe listings per uur", "Float/Int (bijv. 75)", 75.0)

&#x20;           inventory\_q = prompt\_variable("inventory\_q", "Aantal kaarten dat je al bezit van deze speler", "Integer (bijv. 0, 1, 3)", 0)

&#x20;           gamma = prompt\_variable("gamma", "Risico-aversie parameter (hoger = angstiger voor drops)", "Float tussen 0.01 en 0.8", 0.1)

&#x20;           time\_event = prompt\_variable("hours\_to\_event", "Aantal uren tot de volgende 19:00 content drop", "Float (bijv. 3.5)", 4.0)



&#x20;           res = run\_avellaneda\_stoikov(

&#x20;               low\_bin=low\_bin, min\_24h=min\_24h, max\_24h=max\_24h,

&#x20;               sales\_hr=sales\_hr, listings\_hr=listings\_hr,

&#x20;               inventory\_q=inventory\_q, gamma=gamma, time\_to\_event\_hrs=time\_event

&#x20;           )



&#x20;       elif choice == "2":

&#x20;           low\_bin = prompt\_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 35000)", 35000)

&#x20;           sales\_hr = prompt\_variable("sales\_per\_hour", "Aantal gekochte kaarten per uur", "Float (bijv. 80)", 80.0)

&#x20;           listings\_hr = prompt\_variable("listings\_per\_hour", "Aantal aangeboden kaarten per uur", "Float (bijv. 90)", 90.0)

&#x20;           target\_roi = prompt\_variable("target\_roi", "Gewenste netto return on investment (bijv. 0.08 = 8%)", "Float (bijv. 0.08)", 0.08)

&#x20;           holding\_hours = prompt\_variable("holding\_hours", "Maximale gewenste listing duur in uren", "Float (bijv. 1.0)", 1.0)



&#x20;           res = run\_hazard\_rate\_ev(

&#x20;               low\_bin=low\_bin, sales\_hr=sales\_hr, listings\_hr=listings\_hr,

&#x20;               target\_roi=target\_roi, holding\_hours=holding\_hours

&#x20;           )



&#x20;       elif choice == "3":

&#x20;           low\_bin = prompt\_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 65000)", 65000)

&#x20;           avg\_24h = prompt\_variable("avg24", "Gemiddelde 24h prijs op FUTBIN", "Integer (bijv. 72000)", 72000)

&#x20;           min\_24h = prompt\_variable("min24", "24h Laagste prijs", "Integer (bijv. 64000)", 64000)

&#x20;           max\_24h = prompt\_variable("max24", "24h Hoogste prijs", "Integer (bijv. 78000)", 78000)

&#x20;           trend\_pct = prompt\_variable("trend\_pct", "Trend percentage van FUTBIN (bijv. -2.5)", "Float (bijv. -1.5)", -1.5)

&#x20;           diff\_pct = prompt\_variable("diff\_pct", "Verschil percentage t.o.v. gisteren", "Float (bijv. 0.8)", 0.8)



&#x20;           res = run\_ornstein\_uhlenbeck(

&#x20;               low\_bin=low\_bin, avg\_24h=avg\_24h, min\_24h=min\_24h,

&#x20;               max\_24h=max\_24h, trend\_pct=trend\_pct, diff\_pct=diff\_pct

&#x20;           )



&#x20;       elif choice == "4":

&#x20;           card = {

&#x20;               'lowBIN': prompt\_variable("lowBIN", "Actuele laagste Buy-Now prijs", "Integer (bijv. 55000)", 55000),

&#x20;               'avg24': prompt\_variable("avg24", "24-uurs daggemiddelde", "Integer (bijv. 60000)", 60000),

&#x20;               'min24': prompt\_variable("min24", "24-uurs laagste prijs", "Integer (bijv. 53000)", 53000),

&#x20;               'max24': prompt\_variable("max24", "24-uurs hoogste prijs", "Integer (bijv. 66000)", 66000),

&#x20;               'trend\_pct': prompt\_variable("trend\_pct", "FUTBIN Trend %", "Float (bijv. 2.1)", 2.1),

&#x20;               'listings\_per\_hour': prompt\_variable("listings\_per\_hour", "Aantal listings per uur", "Float (bijv. 95)", 95.0),

&#x20;               'sales\_per\_hour': prompt\_variable("sales\_per\_hour", "Aantal verkopen per uur", "Float (bijv. 85)", 85.0),

&#x20;               'price\_min\_range': prompt\_variable("price\_min\_range", "EA Price Band Min", "Integer (bijv. 3000)", 3000),

&#x20;               'price\_max\_range': prompt\_variable("price\_max\_range", "EA Price Band Max", "Integer (bijv. 120000)", 120000)

&#x20;           }

&#x20;           inv\_q = prompt\_variable("inventory\_q", "Aantal kaarten van deze speler in je club/trade pile", "Integer", 0)

&#x20;           budget = prompt\_variable("account\_budget", "Totaal aantal munten op je account", "Integer (bijv. 1500000)", 1500000)

&#x20;           hours\_event = prompt\_variable("hours\_to\_event", "Uren tot volgende content reset", "Float (bijv. 3.0)", 3.0)



&#x20;           res = run\_hybrid\_tos(card, inventory\_q=inv\_q, account\_budget=budget, hours\_to\_event=hours\_event)



&#x20;       else:

&#x20;           print("\[!] Ongeldige keuze.")

&#x20;           continue



&#x20;       # 3. Print Results

&#x20;       print("\\n" + "=" \* 75)

&#x20;       print(f" RESULTATEN: {res.get('model', 'Model Test')}")

&#x20;       print("=" \* 75)

&#x20;       print(json.dumps(res, indent=4))

&#x20;       print("=" \* 75)



&#x20;       input("\\nDruk op Enter om terug te gaan naar het hoofdmenu...")



if \_\_name\_\_ == "\_\_main\_\_":

&#x20;   main()

```



\---



\### Hoe je dit gebruikt:



1\. Kopieer de bovenstaande code en sla hem op als bijvoorbeeld `fc\_pricing\_runner.py`.

2\. Voer het script uit in je terminal:

&#x20;  ```bash

&#x20;  python fc\_pricing\_runner.py

&#x20;  ```

3\. Het script vraagt als eerste naar een directory (bijvoorbeeld `./fc\_pricing`). Het maakt deze direct aan en genereert twee productiegerijpte modules:

&#x20;  \* \*\*`fc26\_pricing\_engine.py`\*\* (klaar om te importeren in je Python bots / analytics pipeline).

&#x20;  \* \*\*`fc26\_pricing\_engine.js`\*\* (klaar om te gebruiken in Node.js of direct in de browser console/Tampermonkey scripts).

4\. Daarna kom je in het interactieve menu waar je elk model los of gecombineerd kunt testen door simpelweg de getallen van een speler in te voeren.

