# Rapport: Kwantitatieve Prijsbepalingsmodellen voor de FC 26 Transfermarkt

## 1. Introductie & Marktspecificaties

Het verhandelen van kaarten op de FC 26 transfermarkt vertoont sterke overeenkomsten met elektronische orderboeken (_limit order books_), maar heeft een aantal specifieke restricties:

1. **EA-Tax Barrière:** $5\%$ frictiekosten over de _bruto verkoopprijs_. De netto-opbrengst is altijd:
   $$\text{Netto Opbrengst} = P_{\text{verkoop}} \times 0{,}95$$
   Een break-even aankoop vereist dus:
   $$P_{\text{koop}} \le 0{,}95 \times P_{\text{verkoop}} \implies P_{\text{verkoop}} \ge \frac{P_{\text{koop}}}{0{,}95} \approx 1{,}0526 \times P_{\text{koop}}$$
2. **Discretisatie & Prijsranges:** Prijzen bewegen in vaste stapgroottes (_ticks_, bijv. stappen van 250 of 500 munten) binnen een vaste bandbreedte $[\text{MinPrice}, \text{MaxPrice}]$.
3. **Geen Short Selling:** Je kunt alleen verkopen wat je bezit.
4. **Data Input Parameters (per speler):**
   - **Tick Data:** Frequentie van listings per uur ($\Lambda_{\text{aanbod}}$), frequentie van transacties per uur ($\Lambda_{\text{verkoop}}$), en individuele transactieprijzen.
   - **Markt Context (FUTBIN e.a.):** $\text{lowBIN}$, $\text{avg}_{24h}$, $\min_{24h}$, $\max_{24h}$, $\text{trend}_{\%}$, $\text{diff}_{\%}$ en het huidige percentage binnen de prijsrange.

---

## 2. Drie Kwantitatieve Benaderingen uit de Literatuur

---

### Benadering 1: Inventory-Risk Adjusted Market Making

**Literatuurbron:** _Avellaneda & Stoikov (2008)_ — voortbouwend op _Ho & Stoll (1981)_.

#### Theoretisch Concept

Een market maker past zijn middenprijs aan naar een _reserveringsprijs_ ($r$). Als de market maker veel voorraad heeft ($q > 0$), daalt de reserveringsprijs om verkopen te versnellen en verdere aankopen te ontmoedigen. De spread wordt bepaald door markvolatiliteit ($\sigma$) en de intensiteit van aankopen bij bepaalde prijzen ($\kappa$).

#### Wiskundige Formulering voor FC 26

1. **Reserveringsprijs ($r$):**
   $$r(s, q, t) = s - q \cdot \gamma \cdot \sigma^2 \cdot (T - t)$$
   - $s$: Huidige benchmarkprijs (bijv. $\text{lowBIN}$ of volume-gewogen mediaan).
   - $q$: Huidige voorraad van spelerX op de transferlijst/club ($0, 1, 2, \dots$).
   - $\gamma$: Risico-aversie parameter (hoe bang ben je voor prijsdalingen).
   - $\sigma$: Volatiliteit berekend uit $(\max_{24h} - \min_{24h}) / s$ of de standaarddeviatie van transacties.
   - $T - t$: Resterende horizon tot marktreset (bijv. uur tot content drop om 19:00).

2. **Optimale Verkoopprijs ($P_{\text{verkoop}}$):**
   $$P_{\text{verkoop}} = \text{round}_{\text{tick}}\left( \frac{r + \frac{1}{\gamma} \ln\left(1 + \frac{\gamma}{\kappa}\right)}{0{,}95} \right)$$
   _Hierbij compenseert de deling door $0{,}95$ voor de EA-tax, zodat de netto-ontvangst matcht met het model._

3. **Optimale Koopprijs / Snipe BIN ($P_{\text{koop}}$):**
   $$P_{\text{koop}} = \text{round\_down}_{\text{tick}}\left( r - \frac{1}{\gamma} \ln\left(1 + \frac{\gamma}{\kappa}\right) \right)$$
   _Waarbij de harde randvoorwaarde geldt dat $P_{\text{koop}} \le 0{,}95 \cdot P_{\text{verkoop}} - \text{Minimale Winstmarge}$._

- $\kappa$ is de liquiditeitsgevoeligheid: hoe steil daalt de kans op verkoop als je de prijs verhoogt (geschat via de verhouding $\Lambda_{\text{verkoop}} / \Lambda_{\text{aanbod}}$).

| Voordelen                                                                         | Nadelen                                                                                  |
| :-------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------- |
| Voorkomt automatische overbevoorrading (dumping-bescherming bij dalende markt).   | Vereist fijnafstelling van abstracte parameters ($\gamma, \kappa$).                      |
| Houdt expliciet rekening met voorraadrisico en resterende tijd tot content drops. | Gaat uit van continue functies; discretisatie naar FC 26-prijsstappen vereist afronding. |

---

### Benadering 2: Hazard Rate & Expected Value Optimization

**Literatuurbron:** _Cont, Stoikov & Talreja (2010)_ en _Survival Analysis in Limit Order Books_.

#### Theoretisch Concept

In plaats van een vaste spread modelleer je de waarschijnlijkheid dat een kaart daadwerkelijk binnen $H$ uur verkocht wordt bij een bepaalde vraagprijs $P$. Dit is een stochastisch optimalisatieprobleem dat de verwachte winst per tijdseenheid maximaliseert.

#### Wiskundige Formulering voor FC 26

1. **Verkoopkans ($P_{\text{fill}}$):**
   De kans dat een kaart binnen $H$ uur verkoopt bij vraagprijs $p$ volgt een Poisson-/exponentieel proces:
   $$\mathbb{P}(\text{Sold} \mid p, H) = 1 - \exp\left(-\lambda(p) \cdot H\right)$$
   Waarbij de verkoopintensiteit $\lambda(p)$ empirisch wordt berekend uit jouw dataset:
   $$\lambda(p) = \Lambda_{\text{verkoop}} \cdot \exp\left(-\beta \cdot \frac{p - \text{lowBIN}}{\text{lowBIN}}\right)$$
   - $\beta$: Gevoeligheidsparameter berekend via historische matches tussen vraag en aanbod.

2. **Verwachte Waarde Functie ($EV$):**
   Voor elke mogelijke discrete verkoopprijs $p \in [\text{lowBIN}, \text{max}_{24h}]$:
   $$EV(p, P_{\text{koop}}) = \mathbb{P}(\text{Sold} \mid p, H) \cdot \left(0{,}95 \cdot p - P_{\text{koop}}\right) - \left(1 - \mathbb{P}(\text{Sold} \mid p, H)\right) \cdot C_{\text{opportunity}}$$
   - $C_{\text{opportunity}}$: Kosten van het bezet houden van een transferlijst-slot.

3. **Prijsbepaling:**
   - **$P_{\text{verkoop}}$:** De prijs $p$ die $EV(p, P_{\text{koop}})$ maximaliseert:
     $$P_{\text{verkoop}} = \arg\max_p EV(p)$$
   - **$P_{\text{koop}}$:** De maximale prijs waarbij $EV(P_{\text{verkoop}}, P_{\text{koop}}) \ge \text{Target ROI} \cdot P_{\text{koop}}$:
     $$P_{\text{koop}} = \frac{0{,}95 \cdot P_{\text{verkoop}} \cdot \mathbb{P}(\text{Sold})}{1 + \text{Target ROI}}$$

| Voordelen                                                                                  | Nadelen                                                                |
| :----------------------------------------------------------------------------------------- | :--------------------------------------------------------------------- |
| Direct gebaseerd op de werkelijke verhouding van aanbod vs. koop per uur.                  | Vereist continue tick-data / orderflow sampling per speler.            |
| Optimaliseert voor _doorloopsnelheid_ (munten per uur) in plaats van pure marge per kaart. | Bij plotselinge marktcrashes loopt de historische $\lambda(p)$ achter. |

---

### Benadering 3: Ornstein-Uhlenbeck Mean-Reversion met Trend-Filter

**Literatuurbron:** _Vasicek (1977)_ / Statistische Arbitrage methodologie.

#### Theoretisch Concept

Kaartprijzen op FUTBIN vertonen sterke _mean-reverting_ eigenschappen rond een glijdend daggemiddelde ($\text{avg}_{24h}$), beïnvloed door dag-en-nacht cycli, maar onderhevig aan een macrotrend ($\text{trend}_{\%}$). Dit model berekent dynamische Bollinger-achtige aankoop- en verkoopdrempels.

#### Wiskundige Formulering voor FC 26

1. **Trend-Aangepast Evenwichtsniveau ($\mu_{\text{target}}$):**
   $$\mu_{\text{target}} = \text{avg}_{24h} \cdot \left(1 + w_1 \cdot \text{trend}_{\%} + w_2 \cdot \text{diff}_{\%}\right)$$
   - $w_1, w_2$: Kalibratiewichten (bijv. $w_1 = 0{,}5, w_2 = 0{,}25$).

2. **Volatiliteit ($\sigma_{\text{rel}}$):**
   $$\sigma_{\text{norm}} = \frac{\max_{24h} - \min_{24h}}{4}$$

3. **Z-Score Berekening van huidige $\text{lowBIN}$:**
   $$Z = \frac{\text{lowBIN} - \mu_{\text{target}}}{\sigma_{\text{norm}}}$$

4. **Prijsbesluit:**
   - **Koopconditie (Snipe target):** Koop alleen als de kaart significant ondergewaardeerd is ($Z \le -k_{\text{entry}}$) én de 5% tax marge gegarandeerd is:
     $$P_{\text{koop}} = \min\left( \text{lowBIN}_{\text{actueel}}, \mu_{\text{target}} - k_{\text{entry}} \cdot \sigma_{\text{norm}} \right)$$
   - **Verkoopdoel ($P_{\text{verkoop}}$):** Verkoop op het verwachte mean-reversion niveau:
     $$P_{\text{verkoop}} = \mu_{\text{target}} + k_{\text{exit}} \cdot \sigma_{\text{norm}}$$
   - **Winst-Check (Harde Filter):**
     $$\text{Verwachte Winst} = (P_{\text{verkoop}} \times 0{,}95) - P_{\text{koop}} > \text{Marge}_{\min}$$
     _Als niet aan deze voorwaarde wordt voldaan, wordt de trade overgeslagen._

| Voordelen                                                                                              | Nadelen                                                             |
| :----------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------ |
| Maakt optimaal gebruik van geaggregeerde FUTBIN-statistieken ($\text{avg}, \min, \max, \text{trend}$). | Minder effectief voor extreem zeldzame kaarten met weinig volume.   |
| Zeer robuust tegen _noise_ en valse dips dankzij het Z-score filter.                                   | Houdt geen rekening met transferlijst-verzadiging (voorraadbeheer). |

---

## 3. Vergelijkingstabel van de Benaderingen

| Eigenschap             | 1. Avellaneda-Stoikov         | 2. Hazard Rate / EV                 | 3. Ornstein-Uhlenbeck / Trend          |
| :--------------------- | :---------------------------- | :---------------------------------- | :------------------------------------- |
| **Primaire Datafocus** | Voorraad ($q$) & Volatiliteit | Aanbod vs. Koop per uur ($\Lambda$) | 24u Gemiddelden, Trend & Min/Max       |
| **Geschikt voor**      | Snipen & Relisten op schaal   | Hoge liquiditeit (meta spelers)     | Fluctuerende SBC/FUT Champions kaarten |
| **Reactiesnelheid**    | Realtime op eigen voorraad    | Realtime op orderflow               | Cyclisch (uren tot dagen)              |
| **Tax-Integratie**     | Analytisch in spread          | Ingebouwd in winstmatrix            | Harde filtering achteraf               |

---

## 4. Implementatieblauwdruk (Python & JavaScript)

Hieronder volgt de logica voor implementatie van het gecombineerde model (waarbij de Trend-Filter de benchmark zet en de EV/Voorraad de uiteindelijke prijzen bepaalt).

### Python Implementatie

```python
import math

def calculate_fc26_prices(card_data, inventory_q=0, target_roi=0.08, min_profit=500):
    """
    card_data: dict met lowBIN, avg24, min24, max24, trend_pct, diff_pct,
              listings_per_hour, sales_per_hour, price_min_range, price_max_range
    """
    low_bin = card_data['lowBIN']
    avg_24 = card_data['avg24']
    trend = card_data['trend_pct'] / 100.0
    listings_hr = card_data['listings_per_hour']
    sales_hr = card_data['sales_per_hour']

    # 1. Bereken Mean-Reversion Target (Trend-aangepast)
    mu_target = avg_24 * (1.0 + 0.5 * trend)

    # 2. Bepaal Listing Spread & Optimale Verkoopprijs (Hazard EV Logica)
    # Als de verkoopintensiteit hoog is relatief tot aanbod, kunnen we boven lowBIN listen
    liquidity_ratio = sales_hr / max(listings_hr, 1)

    if liquidity_ratio > 0.8:
        # Hoge vraag: list rond het daggemiddelde
        raw_sell = max(low_bin, mu_target)
    else:
        # Lage vraag / overaanbod: match lowBIN voor snelle omloop
        raw_sell = low_bin

    # Voorraadcorrectie (Avellaneda-Stoikov afslag bij volle voorraad)
    inventory_penalty = 1.0 - (0.02 * inventory_q) # 2% omlaag per duplicate
    final_sell_price = raw_sell * inventory_penalty

    # Rond af naar FC prijs-tick (bijv. stappen van 250 onder 50k, 500 boven 50k)
    tick = 250 if final_sell_price < 50000 else 500
    p_verkoop = math.floor(final_sell_price / tick) * tick

    # 3. Bereken Maximale Koopprijs (Snipe/Bid) inclusief 5% EA Tax
    net_revenue = p_verkoop * 0.95
    max_buy_price = net_revenue / (1.0 + target_roi) - min_profit

    # Rond koopprijs conservatief af naar beneden
    p_koop = math.floor(max_buy_price / tick) * tick

    # 4. Validatie tegen prijsrange grenzen
    p_koop = max(card_data['price_min_range'], min(p_koop, card_data['price_max_range']))
    p_verkoop = max(card_data['price_min_range'], min(p_verkoop, card_data['price_max_range']))

    # Veiligheidscheck: Garandeer break-even + winst
    expected_profit = (p_verkoop * 0.95) - p_koop
    is_tradable = expected_profit >= min_profit and p_koop < p_verkoop

    return {
        "p_koop_snipe_max": int(p_koop),
        "p_verkoop_list": int(p_verkoop),
        "expected_net_profit": int(expected_profit),
        "expected_roi_pct": round((expected_profit / p_koop) * 100, 2) if p_koop > 0 else 0,
        "is_tradable": is_tradable
    }

# Voorbeeld:
sample_card = {
    'lowBIN': 24000,
    'avg24': 26500,
    'min24': 22000,
    'max24': 28000,
    'trend_pct': -1.5,
    'diff_pct': 0.5,
    'listings_per_hour': 120,
    'sales_per_hour': 110,
    'price_min_range': 1000,
    'price_max_range': 50000
}

print(calculate_fc26_prices(sample_card, inventory_q=1))
```

### JavaScript Implementatie

```javascript
function calculateFC26Prices(
  cardData,
  inventoryQ = 0,
  targetRoi = 0.08,
  minProfit = 500,
) {
  const {
    lowBIN,
    avg24,
    trend_pct,
    listings_per_hour,
    sales_per_hour,
    price_min_range,
    price_max_range,
  } = cardData;

  const trend = trend_pct / 100.0;
  const muTarget = avg24 * (1.0 + 0.5 * trend);

  const liquidityRatio = sales_per_hour / Math.max(listings_per_hour, 1);
  const rawSell = liquidityRatio > 0.8 ? Math.max(lowBIN, muTarget) : lowBIN;

  // Inventory dampening
  const inventoryPenalty = 1.0 - 0.02 * inventoryQ;
  const finalSellPrice = rawSell * inventoryPenalty;

  const tick = finalSellPrice < 50000 ? 250 : 500;
  const pVerkoop = Math.floor(finalSellPrice / tick) * tick;

  const netRevenue = pVerkoop * 0.95;
  const maxBuyPrice = netRevenue / (1.0 + targetRoi) - minProfit;
  const pKoop = Math.floor(maxBuyPrice / tick) * tick;

  const clampedKoop = Math.max(
    price_min_range,
    Math.min(pKoop, price_max_range),
  );
  const clampedVerkoop = Math.max(
    price_min_range,
    Math.min(pVerkoop, price_max_range),
  );

  const expectedProfit = clampedVerkoop * 0.95 - clampedKoop;

  return {
    pKoopSnipeMax: clampedKoop,
    pVerkoopList: clampedVerkoop,
    expectedNetProfit: Math.floor(expectedProfit),
    expectedRoiPct:
      clampedKoop > 0 ? ((expectedProfit / clampedKoop) * 100).toFixed(2) : 0,
    isTradable: expectedProfit >= minProfit && clampedKoop < clampedVerkoop,
  };
}
```

---

## 5. Conclusie & Aanbeveling

1. **Voor Sniping:** Gebruik **Benadering 2 (Hazard/EV)** in combinatie met de vaste tax-formule: snipe op elke listing die minstens $10\%$ onder de reële liquiditeits-BIN valt.
2. **Voor Flipping / Bidding:** Gebruik **Benadering 1 & 3 (Avellaneda-Stoikov + Mean Reversion)**. Hiermee voorkom je dat je te veel voorraad aanhoudt van een speler die in een neerwaartse trend zit, en verkoop je systematisch in de pieken van de dagelijkse fluctuaties.
