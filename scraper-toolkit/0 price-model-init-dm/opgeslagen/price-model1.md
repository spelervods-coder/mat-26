Hieronder vind je het complete rapport in Markdown (`.md`), waarin gevestigde kwantitatieve modellen uit de financiële literatuur worden vertaald naar een concrete prijsberekening voor koop (snipen/bieden) en verkoop (listing) op de FC 26 Ultimate Team transfermarkt.



\*\*\*



\# Rapport: Kwantitatieve Prijsbepalingsmodellen voor de FC 26 Transfermarkt



\## 1. Introductie \& Marktspecificaties



Het verhandelen van kaarten op de FC 26 transfermarkt vertoont sterke overeenkomsten met elektronische orderboeken (\*limit order books\*), maar heeft een aantal specifieke restricties:



1\. \*\*EA-Tax Barrière:\*\* $5\\%$ frictiekosten over de \*bruto verkoopprijs\*. De netto-opbrengst is altijd:

&#x20;  $$\\text{Netto Opbrengst} = P\_{\\text{verkoop}} \\times 0{,}95$$

&#x20;  Een break-even aankoop vereist dus:

&#x20;  $$P\_{\\text{koop}} \\le 0{,}95 \\times P\_{\\text{verkoop}} \\implies P\_{\\text{verkoop}} \\ge \\frac{P\_{\\text{koop}}}{0{,}95} \\approx 1{,}0526 \\times P\_{\\text{koop}}$$

2\. \*\*Discretisatie \& Prijsranges:\*\* Prijzen bewegen in vaste stapgroottes (\*ticks\*, bijv. stappen van 250 of 500 munten) binnen een vaste bandbreedte $\[\\text{MinPrice}, \\text{MaxPrice}]$.

3\. \*\*Geen Short Selling:\*\* Je kunt alleen verkopen wat je bezit.

4\. \*\*Data Input Parameters (per speler):\*\*

&#x20;  \* \*\*Tick Data:\*\* Frequentie van listings per uur ($\\Lambda\_{\\text{aanbod}}$), frequentie van transacties per uur ($\\Lambda\_{\\text{verkoop}}$), en individuele transactieprijzen.

&#x20;  \* \*\*Markt Context (FUTBIN e.a.):\*\* $\\text{lowBIN}$, $\\text{avg}\_{24h}$, $\\min\_{24h}$, $\\max\_{24h}$, $\\text{trend}\_{\\%}$, $\\text{diff}\_{\\%}$ en het huidige percentage binnen de prijsrange.



\---



\## 2. Drie Kwantitatieve Benaderingen uit de Literatuur



\---



\### Benadering 1: Inventory-Risk Adjusted Market Making

\*\*Literatuurbron:\*\* \*Avellaneda \& Stoikov (2008)\* — voortbouwend op \*Ho \& Stoll (1981)\*.



\#### Theoretisch Concept

Een market maker past zijn middenprijs aan naar een \*reserveringsprijs\* ($r$). Als de market maker veel voorraad heeft ($q > 0$), daalt de reserveringsprijs om verkopen te versnellen en verdere aankopen te ontmoedigen. De spread wordt bepaald door markvolatiliteit ($\\sigma$) en de intensiteit van aankopen bij bepaalde prijzen ($\\kappa$).



\#### Wiskundige Formulering voor FC 26

1\. \*\*Reserveringsprijs ($r$):\*\*

&#x20;  $$r(s, q, t) = s - q \\cdot \\gamma \\cdot \\sigma^2 \\cdot (T - t)$$

&#x20;  \* $s$: Huidige benchmarkprijs (bijv. $\\text{lowBIN}$ of volume-gewogen mediaan).

&#x20;  \* $q$: Huidige voorraad van spelerX op de transferlijst/club ($0, 1, 2, \\dots$).

&#x20;  \* $\\gamma$: Risico-aversie parameter (hoe bang ben je voor prijsdalingen).

&#x20;  \* $\\sigma$: Volatiliteit berekend uit $(\\max\_{24h} - \\min\_{24h}) / s$ of de standaarddeviatie van transacties.

&#x20;  \* $T - t$: Resterende horizon tot marktreset (bijv. uur tot content drop om 19:00).



2\. \*\*Optimale Verkoopprijs ($P\_{\\text{verkoop}}$):\*\*

&#x20;  $$P\_{\\text{verkoop}} = \\text{round}\_{\\text{tick}}\\left( \\frac{r + \\frac{1}{\\gamma} \\ln\\left(1 + \\frac{\\gamma}{\\kappa}\\right)}{0{,}95} \\right)$$

&#x20;  \*Hierbij compenseert de deling door $0{,}95$ voor de EA-tax, zodat de netto-ontvangst matcht met het model.\*



3\. \*\*Optimale Koopprijs / Snipe BIN ($P\_{\\text{koop}}$):\*\*

&#x20;  $$P\_{\\text{koop}} = \\text{round\\\_down}\_{\\text{tick}}\\left( r - \\frac{1}{\\gamma} \\ln\\left(1 + \\frac{\\gamma}{\\kappa}\\right) \\right)$$

&#x20;  \*Waarbij de harde randvoorwaarde geldt dat $P\_{\\text{koop}} \\le 0{,}95 \\cdot P\_{\\text{verkoop}} - \\text{Minimale Winstmarge}$.\*



\* $\\kappa$ is de liquiditeitsgevoeligheid: hoe steil daalt de kans op verkoop als je de prijs verhoogt (geschat via de verhouding $\\Lambda\_{\\text{verkoop}} / \\Lambda\_{\\text{aanbod}}$).



| Voordelen | Nadelen |

| :--- | :--- |

| Voorkomt automatische overbevoorrading (dumping-bescherming bij dalende markt). | Vereist fijnafstelling van abstracte parameters ($\\gamma, \\kappa$). |

| Houdt expliciet rekening met voorraadrisico en resterende tijd tot content drops. | Gaat uit van continue functies; discretisatie naar FC 26-prijsstappen vereist afronding. |



\---



\### Benadering 2: Hazard Rate \& Expected Value Optimization

\*\*Literatuurbron:\*\* \*Cont, Stoikov \& Talreja (2010)\* en \*Survival Analysis in Limit Order Books\*.



\#### Theoretisch Concept

In plaats van een vaste spread modelleer je de waarschijnlijkheid dat een kaart daadwerkelijk binnen $H$ uur verkocht wordt bij een bepaalde vraagprijs $P$. Dit is een stochastisch optimalisatieprobleem dat de verwachte winst per tijdseenheid maximaliseert.



\#### Wiskundige Formulering voor FC 26

1\. \*\*Verkoopkans ($P\_{\\text{fill}}$):\*\*

&#x20;  De kans dat een kaart binnen $H$ uur verkoopt bij vraagprijs $p$ volgt een Poisson-/exponentieel proces:

&#x20;  $$\\mathbb{P}(\\text{Sold} \\mid p, H) = 1 - \\exp\\left(-\\lambda(p) \\cdot H\\right)$$

&#x20;  Waarbij de verkoopintensiteit $\\lambda(p)$ empirisch wordt berekend uit jouw dataset:

&#x20;  $$\\lambda(p) = \\Lambda\_{\\text{verkoop}} \\cdot \\exp\\left(-\\beta \\cdot \\frac{p - \\text{lowBIN}}{\\text{lowBIN}}\\right)$$

&#x20;  \* $\\beta$: Gevoeligheidsparameter berekend via historische matches tussen vraag en aanbod.



2\. \*\*Verwachte Waarde Functie ($EV$):\*\*

&#x20;  Voor elke mogelijke discrete verkoopprijs $p \\in \[\\text{lowBIN}, \\text{max}\_{24h}]$:

&#x20;  $$EV(p, P\_{\\text{koop}}) = \\mathbb{P}(\\text{Sold} \\mid p, H) \\cdot \\left(0{,}95 \\cdot p - P\_{\\text{koop}}\\right) - \\left(1 - \\mathbb{P}(\\text{Sold} \\mid p, H)\\right) \\cdot C\_{\\text{opportunity}}$$

&#x20;  \* $C\_{\\text{opportunity}}$: Kosten van het bezet houden van een transferlijst-slot.



3\. \*\*Prijsbepaling:\*\*

&#x20;  \* \*\*$P\_{\\text{verkoop}}$:\*\* De prijs $p$ die $EV(p, P\_{\\text{koop}})$ maximaliseert:

&#x20;    $$P\_{\\text{verkoop}} = \\arg\\max\_p EV(p)$$

&#x20;  \* \*\*$P\_{\\text{koop}}$:\*\* De maximale prijs waarbij $EV(P\_{\\text{verkoop}}, P\_{\\text{koop}}) \\ge \\text{Target ROI} \\cdot P\_{\\text{koop}}$:

&#x20;    $$P\_{\\text{koop}} = \\frac{0{,}95 \\cdot P\_{\\text{verkoop}} \\cdot \\mathbb{P}(\\text{Sold})}{1 + \\text{Target ROI}}$$



| Voordelen | Nadelen |

| :--- | :--- |

| Direct gebaseerd op de werkelijke verhouding van aanbod vs. koop per uur. | Vereist continue tick-data / orderflow sampling per speler. |

| Optimaliseert voor \*doorloopsnelheid\* (munten per uur) in plaats van pure marge per kaart. | Bij plotselinge marktcrashes loopt de historische $\\lambda(p)$ achter. |



\---



\### Benadering 3: Ornstein-Uhlenbeck Mean-Reversion met Trend-Filter

\*\*Literatuurbron:\*\* \*Vasicek (1977)\* / Statistische Arbitrage methodologie.



\#### Theoretisch Concept

Kaartprijzen op FUTBIN vertonen sterke \*mean-reverting\* eigenschappen rond een glijdend daggemiddelde ($\\text{avg}\_{24h}$), beïnvloed door dag-en-nacht cycli, maar onderhevig aan een macrotrend ($\\text{trend}\_{\\%}$). Dit model berekent dynamische Bollinger-achtige aankoop- en verkoopdrempels.



\#### Wiskundige Formulering voor FC 26

1\. \*\*Trend-Aangepast Evenwichtsniveau ($\\mu\_{\\text{target}}$):\*\*

&#x20;  $$\\mu\_{\\text{target}} = \\text{avg}\_{24h} \\cdot \\left(1 + w\_1 \\cdot \\text{trend}\_{\\%} + w\_2 \\cdot \\text{diff}\_{\\%}\\right)$$

&#x20;  \* $w\_1, w\_2$: Kalibratiewichten (bijv. $w\_1 = 0{,}5, w\_2 = 0{,}25$).



2\. \*\*Volatiliteit ($\\sigma\_{\\text{rel}}$):\*\*

&#x20;  $$\\sigma\_{\\text{norm}} = \\frac{\\max\_{24h} - \\min\_{24h}}{4}$$



3\. \*\*Z-Score Berekening van huidige $\\text{lowBIN}$:\*\*

&#x20;  $$Z = \\frac{\\text{lowBIN} - \\mu\_{\\text{target}}}{\\sigma\_{\\text{norm}}}$$



4\. \*\*Prijsbesluit:\*\*

&#x20;  \* \*\*Koopconditie (Snipe target):\*\* Koop alleen als de kaart significant ondergewaardeerd is ($Z \\le -k\_{\\text{entry}}$) én de 5% tax marge gegarandeerd is:

&#x20;    $$P\_{\\text{koop}} = \\min\\left( \\text{lowBIN}\_{\\text{actueel}}, \\mu\_{\\text{target}} - k\_{\\text{entry}} \\cdot \\sigma\_{\\text{norm}} \\right)$$

&#x20;  \* \*\*Verkoopdoel ($P\_{\\text{verkoop}}$):\*\* Verkoop op het verwachte mean-reversion niveau:

&#x20;    $$P\_{\\text{verkoop}} = \\mu\_{\\text{target}} + k\_{\\text{exit}} \\cdot \\sigma\_{\\text{norm}}$$

&#x20;  \* \*\*Winst-Check (Harde Filter):\*\*

&#x20;    $$\\text{Verwachte Winst} = (P\_{\\text{verkoop}} \\times 0{,}95) - P\_{\\text{koop}} > \\text{Marge}\_{\\min}$$

&#x20;    \*Als niet aan deze voorwaarde wordt voldaan, wordt de trade overgeslagen.\*



| Voordelen | Nadelen |

| :--- | :--- |

| Maakt optimaal gebruik van geaggregeerde FUTBIN-statistieken ($\\text{avg}, \\min, \\max, \\text{trend}$). | Minder effectief voor extreem zeldzame kaarten met weinig volume. |

| Zeer robuust tegen \*noise\* en valse dips dankzij het Z-score filter. | Houdt geen rekening met transferlijst-verzadiging (voorraadbeheer). |



\---



\## 3. Vergelijkingstabel van de Benaderingen



| Eigenschap | 1. Avellaneda-Stoikov | 2. Hazard Rate / EV | 3. Ornstein-Uhlenbeck / Trend |

| :--- | :--- | :--- | :--- |

| \*\*Primaire Datafocus\*\* | Voorraad ($q$) \& Volatiliteit | Aanbod vs. Koop per uur ($\\Lambda$) | 24u Gemiddelden, Trend \& Min/Max |

| \*\*Geschikt voor\*\* | Snipen \& Relisten op schaal | Hoge liquiditeit (meta spelers) | Fluctuerende SBC/FUT Champions kaarten |

| \*\*Reactiesnelheid\*\* | Realtime op eigen voorraad | Realtime op orderflow | Cyclisch (uren tot dagen) |

| \*\*Tax-Integratie\*\* | Analytisch in spread | Ingebouwd in winstmatrix | Harde filtering achteraf |



\---



\## 4. Implementatieblauwdruk (Python \& JavaScript)



Hieronder volgt de logica voor implementatie van het gecombineerde model (waarbij de Trend-Filter de benchmark zet en de EV/Voorraad de uiteindelijke prijzen bepaalt).



\### Python Implementatie



```python

import math



def calculate\_fc26\_prices(card\_data, inventory\_q=0, target\_roi=0.08, min\_profit=500):

&#x20;   """

&#x20;   card\_data: dict met lowBIN, avg24, min24, max24, trend\_pct, diff\_pct, 

&#x20;             listings\_per\_hour, sales\_per\_hour, price\_min\_range, price\_max\_range

&#x20;   """

&#x20;   low\_bin = card\_data\['lowBIN']

&#x20;   avg\_24 = card\_data\['avg24']

&#x20;   trend = card\_data\['trend\_pct'] / 100.0

&#x20;   listings\_hr = card\_data\['listings\_per\_hour']

&#x20;   sales\_hr = card\_data\['sales\_per\_hour']

&#x20;   

&#x20;   # 1. Bereken Mean-Reversion Target (Trend-aangepast)

&#x20;   mu\_target = avg\_24 \* (1.0 + 0.5 \* trend)

&#x20;   

&#x20;   # 2. Bepaal Listing Spread \& Optimale Verkoopprijs (Hazard EV Logica)

&#x20;   # Als de verkoopintensiteit hoog is relatief tot aanbod, kunnen we boven lowBIN listen

&#x20;   liquidity\_ratio = sales\_hr / max(listings\_hr, 1)

&#x20;   

&#x20;   if liquidity\_ratio > 0.8:

&#x20;       # Hoge vraag: list rond het daggemiddelde

&#x20;       raw\_sell = max(low\_bin, mu\_target)

&#x20;   else:

&#x20;       # Lage vraag / overaanbod: match lowBIN voor snelle omloop

&#x20;       raw\_sell = low\_bin

&#x20;   

&#x20;   # Voorraadcorrectie (Avellaneda-Stoikov afslag bij volle voorraad)

&#x20;   inventory\_penalty = 1.0 - (0.02 \* inventory\_q) # 2% omlaag per duplicate

&#x20;   final\_sell\_price = raw\_sell \* inventory\_penalty

&#x20;   

&#x20;   # Rond af naar FC prijs-tick (bijv. stappen van 250 onder 50k, 500 boven 50k)

&#x20;   tick = 250 if final\_sell\_price < 50000 else 500

&#x20;   p\_verkoop = math.floor(final\_sell\_price / tick) \* tick

&#x20;   

&#x20;   # 3. Bereken Maximale Koopprijs (Snipe/Bid) inclusief 5% EA Tax

&#x20;   net\_revenue = p\_verkoop \* 0.95

&#x20;   max\_buy\_price = net\_revenue / (1.0 + target\_roi) - min\_profit

&#x20;   

&#x20;   # Rond koopprijs conservatief af naar beneden

&#x20;   p\_koop = math.floor(max\_buy\_price / tick) \* tick

&#x20;   

&#x20;   # 4. Validatie tegen prijsrange grenzen

&#x20;   p\_koop = max(card\_data\['price\_min\_range'], min(p\_koop, card\_data\['price\_max\_range']))

&#x20;   p\_verkoop = max(card\_data\['price\_min\_range'], min(p\_verkoop, card\_data\['price\_max\_range']))

&#x20;   

&#x20;   # Veiligheidscheck: Garandeer break-even + winst

&#x20;   expected\_profit = (p\_verkoop \* 0.95) - p\_koop

&#x20;   is\_tradable = expected\_profit >= min\_profit and p\_koop < p\_verkoop

&#x20;   

&#x20;   return {

&#x20;       "p\_koop\_snipe\_max": int(p\_koop),

&#x20;       "p\_verkoop\_list": int(p\_verkoop),

&#x20;       "expected\_net\_profit": int(expected\_profit),

&#x20;       "expected\_roi\_pct": round((expected\_profit / p\_koop) \* 100, 2) if p\_koop > 0 else 0,

&#x20;       "is\_tradable": is\_tradable

&#x20;   }



\# Voorbeeld:

sample\_card = {

&#x20;   'lowBIN': 24000,

&#x20;   'avg24': 26500,

&#x20;   'min24': 22000,

&#x20;   'max24': 28000,

&#x20;   'trend\_pct': -1.5,

&#x20;   'diff\_pct': 0.5,

&#x20;   'listings\_per\_hour': 120,

&#x20;   'sales\_per\_hour': 110,

&#x20;   'price\_min\_range': 1000,

&#x20;   'price\_max\_range': 50000

}



print(calculate\_fc26\_prices(sample\_card, inventory\_q=1))

```



\### JavaScript Implementatie



```javascript

function calculateFC26Prices(cardData, inventoryQ = 0, targetRoi = 0.08, minProfit = 500) {

&#x20;   const { lowBIN, avg24, trend\_pct, listings\_per\_hour, sales\_per\_hour, price\_min\_range, price\_max\_range } = cardData;

&#x20;   

&#x20;   const trend = trend\_pct / 100.0;

&#x20;   const muTarget = avg24 \* (1.0 + 0.5 \* trend);

&#x20;   

&#x20;   const liquidityRatio = sales\_per\_hour / Math.max(listings\_per\_hour, 1);

&#x20;   const rawSell = (liquidityRatio > 0.8) ? Math.max(lowBIN, muTarget) : lowBIN;

&#x20;   

&#x20;   // Inventory dampening

&#x20;   const inventoryPenalty = 1.0 - (0.02 \* inventoryQ);

&#x20;   const finalSellPrice = rawSell \* inventoryPenalty;

&#x20;   

&#x20;   const tick = finalSellPrice < 50000 ? 250 : 500;

&#x20;   const pVerkoop = Math.floor(finalSellPrice / tick) \* tick;

&#x20;   

&#x20;   const netRevenue = pVerkoop \* 0.95;

&#x20;   const maxBuyPrice = (netRevenue / (1.0 + targetRoi)) - minProfit;

&#x20;   const pKoop = Math.floor(maxBuyPrice / tick) \* tick;

&#x20;   

&#x20;   const clampedKoop = Math.max(price\_min\_range, Math.min(pKoop, price\_max\_range));

&#x20;   const clampedVerkoop = Math.max(price\_min\_range, Math.min(pVerkoop, price\_max\_range));

&#x20;   

&#x20;   const expectedProfit = (clampedVerkoop \* 0.95) - clampedKoop;

&#x20;   

&#x20;   return {

&#x20;       pKoopSnipeMax: clampedKoop,

&#x20;       pVerkoopList: clampedVerkoop,

&#x20;       expectedNetProfit: Math.floor(expectedProfit),

&#x20;       expectedRoiPct: clampedKoop > 0 ? ((expectedProfit / clampedKoop) \* 100).toFixed(2) : 0,

&#x20;       isTradable: expectedProfit >= minProfit \&\& clampedKoop < clampedVerkoop

&#x20;   };

}

```



\---



\## 5. Conclusie \& Aanbeveling



1\. \*\*Voor Sniping Bots:\*\* Gebruik \*\*Benadering 2 (Hazard/EV)\*\* in combinatie met de vaste tax-formule: snipe op elke listing die minstens $10\\%$ onder de reële liquiditeits-BIN valt.

2\. \*\*Voor Flipping / Mass Bidding:\*\* Gebruik \*\*Benadering 1 \& 3 (Avellaneda-Stoikov + Mean Reversion)\*\*. Hiermee voorkom je dat je te veel voorraad aanhoudt van een speler die in een neerwaartse trend zit, en verkoop je systematisch in de pieken van de dagelijkse fluctuaties.

