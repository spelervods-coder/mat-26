\*\*Ja, absoluut.\*\* Het hanteren van een vast winstpercentage (zoals een statische $5\\%$ of $8\\%$ ROI) is een naïeve vuistregel. In de kwantitatieve handel en marktmaker-literatuur moet het winstpercentage een \*\*endogene (zelfoptimaliserende) variabele\*\* zijn. 



Het doel is namelijk niet \*maximale marge per kaart\*, maar \*\*maximale totale winststroom per tijdseenheid per transferlijst-slot ($\\text{Munten / Uur / Slot}$)\*\*.



\---



\### 1. Het Fundamentele Dilemma: Marge vs. Omloopsnelheid (\*Coin Velocity\*)



Als je een vast percentage instelt, loop je tegen twee inefficiënties aan:



```

Verwachte Winst/Uur

&#x20;      ▲

&#x20;      │             Optimale Marge (Sweet Spot)

&#x20; Max  │                   ┌───────┐

Winst  │                  ┌┘       └┐

&#x20;/Uur  │                 ┌┘         └┐

&#x20;      │                ┌┘           └┐

&#x20;      │               ┌┘             └┐  Te hoge marge:

&#x20;      │  Te lage marge:                └┐Kaart verkoopt niet,

&#x20;      │  Veel flips, te                  slot zit 12u geblokkeerd

&#x20;      │  weinig opbrengst na 5% tax

&#x20;      └───────────────────────────────────► Winstmarge / Spread

```



1\. \*\*Marge te hoog gezet:\*\* Je pakt misschien $15\\%$ winst op een kaart van $50.000$ munten ($+7.500$), maar het duurt $8$ uur voor hij verkoopt. 

&#x20;  $$\\text{Winststroom} = \\frac{7.500}{8\\text{ uur}} = 937{,}5\\text{ munten/uur}$$

2\. \*\*Marge optimaal afgestemd op liquiditeit:\*\* Je pakt $6\\%$ winst ($+3.000$), maar de kaart verkoopt gegarandeerd binnen $45$ minuten. Je kunt dit slot in diezelfde 8 uur 10 keer hergebruiken.

&#x20;  $$\\text{Winststroom} = \\frac{3.000}{0{,}75\\text{ uur}} = 4.000\\text{ munten/uur}$$



\---



\### 2. Wiskundige Formulering voor Winstmaximalisatie



In de literatuur over \*Optimal Limit Order Placement\* (o.a. \*Guéant, Tapia \& Zou, 2012\*) maximaliseer je de verwachte winst per tijdseenheid $\\mathbb{E}\[\\Pi\_{\\Delta t}]$ als een functie van zowel de aankoop- als verkoopprijs:



$$\\max\_{P\_{\\text{koop}}, P\_{\\text{verkoop}}} \\mathbb{E}\[\\text{Winststroom}] = \\frac{\\mathbb{P}\_{\\text{buy}}(P\_{\\text{koop}}) \\cdot \\left(0{,}95 \\cdot P\_{\\text{verkoop}} - P\_{\\text{koop}}\\right)}{\\mathbb{E}\[T\_{\\text{koop}}(P\_{\\text{koop}})] + \\mathbb{E}\[T\_{\\text{verkoop}}(P\_{\\text{verkoop}})]}$$



Waarbij:

\* \*\*$\\mathbb{P}\_{\\text{buy}}(P\_{\\text{koop}})$:\*\* De kans dat een snipe/bod slaagt bij koopprijs $P\_{\\text{koop}}$. Hoe dichter je bij $\\text{lowBIN}$ biedt, hoe hoger de kans op een succesvolle aankoop, maar hoe lager de marge.

\* \*\*$0{,}95 \\cdot P\_{\\text{verkoop}} - P\_{\\text{koop}}$:\*\* De absolute nettowinst na aftrek van EA-tax.

\* \*\*$\\mathbb{E}\[T\_{\\text{verkoop}}]$:\*\* De verwachte bewaartijd tot verkoop, gemodelleerd via de Poisson/Hazard rate:

&#x20; $$\\mathbb{E}\[T\_{\\text{verkoop}}] = \\frac{1}{\\lambda(P\_{\\text{verkoop}})} = \\frac{1}{\\Lambda\_{\\text{verkoop}} \\cdot e^{-\\kappa \\cdot \\frac{P\_{\\text{verkoop}} - \\text{lowBIN}}{\\text{lowBIN}}}}$$



\---



\### 3. De Twee Bottlenecks: Kapitaal vs. Transferlijst-Slots



Welke marge optimaal is voor maximale winst hangt af van \*\*welke restrictie op dat moment bindend is\*\*:



| Situatie | Bindende Factor | Optimale Strategie | Doelstelling Marge |

| :--- | :--- | :--- | :--- |

| \*\*Volle Transferlijst (100/100 slots bezet)\*\* | \*\*Slot-Capaciteit\*\* | \*Hoge omloopsnelheid\*: Verlaag je winstmarge naar het minimum dat net boven het tax-risico ligt. Elk uur dat een slot geblokkeerd is, kost potentiële flips. | Dynamische ROI: \*\*$3\\% - 5\\%$\*\* |

| \*\*Weinig Munten (Budget-beperkt)\*\* | \*\*Kapitaal\*\* | \*Maximaliseer ROI per coin\*: Zolang je slots vrij hebt, moet elke geïnvesteerde munt maximaal renderen. | Dynamische ROI: \*\*$8\\% - 15\\%$\*\* |

| \*\*Hoge Liquiditeit / Hype Kaart\*\* ($\\Lambda\_{\\text{sales}} \\gg \\Lambda\_{\\text{listings}}$) | \*\*Marktaanbod\*\* | \*Prijselasticiteit is laag\*: Kopers accepteren overbieden. Verhoog de marge dynamisch. | Dynamische ROI: \*\*$10\\% - 20\\%$\*\* |



\---



\### 4. Hoe bereken je de Optimale Marge Endogeen?



In plaats van een vaste parameter `target\_roi = 0.08`, gebruik je de \*\*Lerner-index uit de micro-economie\*\* en de \*\*Hazard-elasticiteit ($\\kappa$)\*\*:



$$\\text{Optimale Marge-opslag } \\delta^\* = \\frac{1}{\\kappa} = \\frac{\\text{lowBIN} \\cdot \\Lambda\_{\\text{aanbod}}}{\\Lambda\_{\\text{verkoop}}}$$



Dit resulteert in een zelfstellende formule voor de maximale koopprijs:



$$P\_{\\text{koop}}^\* = \\arg\\max\_{P} \\left\[ \\left(0{,}95 \\cdot P\_{\\text{verkoop}} - P\\right) \\cdot \\left(1 - e^{-\\Lambda\_{\\text{listings}} \\cdot \\left(\\frac{P}{\\text{lowBIN}}\\right)^{\\alpha}}\\right) \\right]$$



\---



\### 5. Code-Aanpassing: De Zelf-Optimaliserende Marge Grid Search



In plaats van een statische marge zoekt dit algoritme over een grid van mogelijke marges de waarde die de \*\*Verwachte Winst per Uur\*\* maximaliseert:



```python

import math



def calculate\_profit\_maximizing\_prices(card, slots\_available=20, coin\_budget=500\_000):

&#x20;   low\_bin = float(card\['lowBIN'])

&#x20;   listings\_hr = max(float(card\['listings\_per\_hour']), 1.0)

&#x20;   sales\_hr = max(float(card\['sales\_per\_hour']), 1.0)

&#x20;   

&#x20;   # 1. Bepaal omloopfactor (Fill rate intensity)

&#x20;   base\_fill\_rate = sales\_hr / listings\_hr

&#x20;   

&#x20;   # 2. Simuleer verschillende mogelijke bruto verkoopprijzen rond de lowBIN

&#x20;   best\_expected\_profit\_per\_hour = -float('inf')

&#x20;   best\_p\_sell = low\_bin

&#x20;   best\_p\_buy = low\_bin \* 0.85

&#x20;   best\_optimal\_roi = 0.0



&#x20;   # Grid search: test verkoop tussen -2% en +8% van lowBIN

&#x20;   for markup\_pct in \[-0.02, -0.01, 0.0, 0.01, 0.02, 0.04, 0.06, 0.08]:

&#x20;       p\_sell\_candidate = low\_bin \* (1.0 + markup\_pct)

&#x20;       net\_revenue = p\_sell\_candidate \* 0.95

&#x20;       

&#x20;       # Kans op verkoop binnen 1 uur daalt naarmate de listingprijs stijgt

&#x20;       decay\_factor = math.exp(-3.0 \* max(0.0, markup\_pct))

&#x20;       p\_sold\_1h = 1.0 - math.exp(-base\_fill\_rate \* decay\_factor)

&#x20;       expected\_hold\_time\_hours = 1.0 / max(base\_fill\_rate \* decay\_factor, 0.1)



&#x20;       # Test verschillende koopprijzen (snipe thresholds)

&#x20;       for buy\_discount in \[0.06, 0.08, 0.10, 0.12, 0.15, 0.20]:

&#x20;           p\_buy\_candidate = net\_revenue \* (1.0 - buy\_discount)

&#x20;           

&#x20;           # Kans dat een snipe succesvol binnenkomt (hoger bod = snellere aankoop)

&#x20;           p\_buy\_success\_rate = min(1.0, (p\_buy\_candidate / (low\_bin \* 0.95)) \*\* 4)

&#x20;           expected\_buy\_time\_hours = 1.0 / (listings\_hr \* p\_buy\_success\_rate + 0.1)

&#x20;           

&#x20;           # Absolute nettowinst na EA Tax

&#x20;           net\_profit = net\_revenue - p\_buy\_candidate

&#x20;           

&#x20;           if net\_profit < 350:  # Minimum absolute winstvloer

&#x20;               continue



&#x20;           # Totale verwachte cyclusduur (wachten op aankoop + wachten op verkoop)

&#x20;           total\_cycle\_time = expected\_buy\_time\_hours + expected\_hold\_time\_hours

&#x20;           

&#x20;           # DOELFUNCTIE: Winst per Uur per Slot

&#x20;           expected\_profit\_per\_hour = (net\_profit \* p\_sold\_1h) / total\_cycle\_time

&#x20;           

&#x20;           # Slot-penalty: Als transferlijst vol raakt, forceer kortere cyclus

&#x20;           if slots\_available < 10:

&#x20;               expected\_profit\_per\_hour \*= (1.0 / total\_cycle\_time)



&#x20;           if expected\_profit\_per\_hour > best\_expected\_profit\_per\_hour:

&#x20;               best\_expected\_profit\_per\_hour = expected\_profit\_per\_hour

&#x20;               best\_p\_sell = p\_sell\_candidate

&#x20;               best\_p\_buy = p\_buy\_candidate

&#x20;               best\_optimal\_roi = net\_profit / p\_buy\_candidate



&#x20;   return {

&#x20;       "p\_koop\_snipe\_max": int(best\_p\_buy),

&#x20;       "p\_verkoop\_list": int(best\_p\_sell),

&#x20;       "netto\_winst": int((best\_p\_sell \* 0.95) - best\_p\_buy),

&#x20;       "dynamisch\_geoptimaliseerde\_roi": f"{round(best\_optimal\_roi \* 100, 2)}%",

&#x20;       "verwachte\_winst\_per\_uur": int(best\_expected\_profit\_per\_hour)

&#x20;   }

```



\---



\### Conclusie



Winstmaximalisatie betekent \*\*het optimaliseren van het product van Marge $\\times$ Snelheid\*\*:

1\. \*\*Snelle, liquide spelers\*\* (meta kaarten met 100+ sales/uur) $\\to$ \*\*Lage winstmarge ($4\\% - 6\\%$)\*\*, want je kunt het kapitaal 4 keer per uur rondpompen.

2\. \*\*Trage, illiquide spelers\*\* (hoge ratings, SBC-fodder met weinig listings) $\\to$ \*\*Hoge winstmarge ($12\\% - 20\\%$)\*\*, omdat de kaart uren een transferlijst-slot bezet houdt en dat gecompenseerd moet worden in absolute winst.

